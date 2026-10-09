// Command go-mod-replacer applies local and global Go module overrides.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"golang.org/x/mod/modfile"
	"golang.org/x/mod/module"
	"golang.org/x/mod/semver"
)

type modulePolicy struct {
	TargetVersion string `json:"targetVersion"`
	CVEs          string `json:"cves"`
	MinimumGo     string `json:"minimumGo"`
}

type policy struct {
	Modules map[string]modulePolicy `json:"modules"`
}

func loadPolicy(path string) (policy, error) {
	file, err := os.Open(path)
	if err != nil {
		return policy{}, err
	}
	defer file.Close()
	decoder := json.NewDecoder(file)
	decoder.DisallowUnknownFields()
	var result policy
	if err := decoder.Decode(&result); err != nil {
		return policy{}, err
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return policy{}, fmt.Errorf("policy must contain one JSON object")
	}
	if result.Modules == nil {
		return policy{}, fmt.Errorf("policy must contain modules")
	}
	for name, entry := range result.Modules {
		if err := module.Check(name, entry.TargetVersion); err != nil {
			return policy{}, fmt.Errorf("invalid module policy %s: %w", name, err)
		}
		if semver.Canonical(entry.TargetVersion) != entry.TargetVersion || !semver.IsValid("v"+entry.MinimumGo) || entry.CVEs == "" {
			return policy{}, fmt.Errorf("invalid module policy: %s", name)
		}
	}
	return result, nil
}

func readLocalOverrides(path string) ([][]string, map[string]bool, error) {
	contents, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil, map[string]bool{}, nil
	}
	if err != nil {
		return nil, nil, err
	}
	var directives [][]string
	result := make(map[string]bool)
	for index, line := range strings.Split(string(contents), "\n") {
		fields := strings.Fields(strings.SplitN(line, "#", 2)[0])
		if len(fields) == 0 {
			continue
		}
		flagName, value, inline := strings.Cut(fields[0], "=")
		if flagName != "-replace" || (inline && len(fields) != 1) || (!inline && len(fields) != 2) {
			return nil, nil, fmt.Errorf("%s:%d: expected a single -replace entry", path, index+1)
		}
		if !inline {
			value = fields[1]
		}
		old, replacement, found := strings.Cut(value, "=")
		if !found || old == "" || replacement == "" {
			return nil, nil, fmt.Errorf("%s:%d: expected -replace=module[@version]=replacement[@version]", path, index+1)
		}
		name := strings.SplitN(old, "@", 2)[0]
		result[name] = true
		directives = append(directives, fields)
	}
	return directives, result, nil
}

func localModules(path string) (map[string]bool, error) {
	_, selected, err := readLocalOverrides(path)
	return selected, err
}

func plan(currentPolicy policy, directory, overrides, goVersion string, workspace bool) ([]string, error) {
	selected, err := localModules(overrides)
	if err != nil {
		return nil, err
	}
	paths := []string{filepath.Join(directory, "go.mod")}
	if workspace {
		path := filepath.Join(directory, "go.work")
		contents, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		work, err := modfile.ParseWork(path, contents, nil)
		if err != nil {
			return nil, err
		}
		paths = nil
		for _, use := range work.Use {
			moduleDir := use.Path
			if !filepath.IsAbs(moduleDir) {
				moduleDir = filepath.Join(directory, moduleDir)
			}
			paths = append(paths, filepath.Join(moduleDir, "go.mod"))
		}
		for _, replacement := range work.Replace {
			selected[replacement.Old.Path] = true
		}
	}
	versions := make(map[string]string)
	for _, path := range paths {
		contents, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		file, err := modfile.Parse(path, contents, nil)
		if err != nil {
			return nil, err
		}
		for _, requirement := range file.Require {
			name := requirement.Mod.Path
			if semver.Compare(requirement.Mod.Version, versions[name]) > 0 {
				versions[name] = requirement.Mod.Version
			}
		}
		for _, replacement := range file.Replace {
			selected[replacement.Old.Path] = true
		}
	}
	names := make([]string, 0, len(currentPolicy.Modules))
	for name := range currentPolicy.Modules {
		names = append(names, name)
	}
	sort.Strings(names)
	var directives []string
	for _, name := range names {
		entry := currentPolicy.Modules[name]
		version, present := versions[name]
		if !present || selected[name] || semver.Compare(version, entry.TargetVersion) >= 0 {
			continue
		}
		if semver.Compare("v"+strings.TrimPrefix(goVersion, "go"), "v"+entry.MinimumGo) < 0 {
			fmt.Fprintf(os.Stderr, "go-mod-replacer: skipping global replacement %s@%s: requires Go %s; compiler is %s\n", name, entry.TargetVersion, entry.MinimumGo, goVersion)
			continue
		}
		directives = append(directives, "-replace="+name+"="+name+"@"+entry.TargetVersion)
	}
	return directives, nil
}

func applyOverrides(currentPolicy policy, directory, overrides, goVersion string, workspace bool, runGo func(...string) error) error {
	localDirectives, _, err := readLocalOverrides(overrides)
	if err != nil {
		return err
	}
	mode := "mod"
	if workspace {
		mode = "work"
	}
	for _, directive := range localDirectives {
		if err := runGo(append([]string{mode, "edit"}, directive...)...); err != nil {
			return err
		}
	}
	directives, err := plan(currentPolicy, directory, overrides, goVersion, workspace)
	if err != nil {
		return err
	}
	for _, directive := range directives {
		if err := runGo(mode, "edit", directive); err != nil {
			return err
		}
	}
	if !workspace {
		if err := runGo("mod", "tidy"); err != nil {
			return err
		}
	}
	if info, err := os.Stat(filepath.Join(directory, "vendor")); err == nil && info.IsDir() {
		return runGo(mode, "vendor")
	} else if err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

func run() error {
	policyPath := flag.String("global", "/usr/local/share/go-mod-replacer/global_overrides.json", "global override policy")
	overrides := flag.String("local", "go-mod-overrides", "local overrides to apply before global overrides")
	workspace := flag.Bool("workspace", false, "apply overrides to go.work (also detected automatically unless GOWORK=off)")
	flag.Parse()
	if flag.NArg() > 1 {
		return fmt.Errorf("usage: go-mod-replacer [flags] [OVERRIDES_FILE]")
	}
	if flag.NArg() == 1 {
		*overrides = flag.Arg(0)
	}
	if info, err := os.Stat("go.work"); err == nil && !info.IsDir() && os.Getenv("GOWORK") != "off" {
		*workspace = true
	}
	currentPolicy, err := loadPolicy(*policyPath)
	if err != nil {
		return err
	}
	version, err := exec.Command("go", "env", "GOVERSION").Output()
	if err != nil {
		return err
	}
	return applyOverrides(currentPolicy, ".", *overrides, strings.TrimSpace(string(version)), *workspace, func(arguments ...string) error {
		fmt.Printf("go-mod-replacer: go %s\n", strings.Join(arguments, " "))
		command := exec.Command("go", arguments...)
		command.Stdout, command.Stderr = os.Stdout, os.Stderr
		return command.Run()
	})
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "go-mod-replacer: %v\n", err)
		os.Exit(1)
	}
}
