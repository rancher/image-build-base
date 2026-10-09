package main

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func writeFile(t *testing.T, path, contents string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
		t.Fatal(err)
	}
}

func testPolicy() policy {
	return policy{Modules: map[string]modulePolicy{
		"golang.org/x/crypto": {TargetVersion: "v0.56.0", CVEs: "CVE-2026-56855", MinimumGo: "1.26.0"},
	}}
}

func TestLoadPolicy(t *testing.T) {
	for _, test := range []struct {
		name     string
		contents string
		valid    bool
	}{
		{"valid", `{"modules":{"golang.org/x/crypto":{"targetVersion":"v0.56.0","cves":"CVE-2026-56855","minimumGo":"1.26.0"}}}`, true},
		{"empty", `{"modules":{}}`, true},
		{"repositories removed", `{"modules":{},"repositories":[]}`, false},
		{"missing modules", `{}`, false},
		{"invalid version", `{"modules":{"golang.org/x/crypto":{"targetVersion":"bad","cves":"CVE-2026-56855","minimumGo":"1.26.0"}}}`, false},
		{"extra object", `{"modules":{}} {}`, false},
	} {
		t.Run(test.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "policy.json")
			writeFile(t, path, test.contents)
			_, err := loadPolicy(path)
			if (err == nil) != test.valid {
				t.Fatalf("loadPolicy error = %v, valid = %t", err, test.valid)
			}
		})
	}
}

func TestReadLocalOverrides(t *testing.T) {
	for _, test := range []struct {
		name     string
		contents string
		want     [][]string
		wantErr  bool
	}{
		{name: "comments and blanks", contents: "# comment\n\n  # indented\n"},
		{name: "space form", contents: " -replace example.com/local=../local # comment\n", want: [][]string{{"-replace", "example.com/local=../local"}}},
		{name: "equals form", contents: "-replace=example.com/local@v1.0.0=example.com/fork@v1.1.0", want: [][]string{{"-replace=example.com/local@v1.0.0=example.com/fork@v1.1.0"}}},
		{name: "require", contents: "-require=example.com/local@v1.0.0", wantErr: true},
		{name: "drop replacement", contents: "-dropreplace=example.com/local", wantErr: true},
		{name: "go version", contents: "-go=1.22.0", wantErr: true},
		{name: "extra flag", contents: "-replace=example.com/local=../local -go=1.22.0", wantErr: true},
		{name: "missing argument", contents: "-replace", wantErr: true},
		{name: "missing target", contents: "-replace=example.com/local=", wantErr: true},
		{name: "missing source", contents: "-replace==../local", wantErr: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "go-mod-overrides")
			writeFile(t, path, test.contents)
			got, selected, err := readLocalOverrides(path)
			if (err != nil) != test.wantErr {
				t.Fatalf("readLocalOverrides error = %v", err)
			}
			if test.wantErr {
				if !strings.Contains(err.Error(), path+":1:") {
					t.Fatalf("error lacks file and line: %v", err)
				}
				return
			}
			if !reflect.DeepEqual(got, test.want) {
				t.Fatalf("directives = %v, want %v", got, test.want)
			}
			if len(got) != 0 && !selected["example.com/local"] {
				t.Fatalf("local module not selected: %v", selected)
			}
		})
	}
}

func TestApplyOverridesRejectsInvalidLocalBeforeEdits(t *testing.T) {
	for _, test := range []struct {
		name      string
		workspace bool
	}{
		{name: "module"},
		{name: "workspace", workspace: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			directory := t.TempDir()
			local := filepath.Join(directory, "go-mod-overrides")
			writeFile(t, local, "-replace=example.com/local=../local\n-require=example.com/other@v1.0.0\n")
			calls := 0
			err := applyOverrides(testPolicy(), directory, local, "go1.26.9", test.workspace, func(...string) error {
				calls++
				return nil
			})
			if err == nil || !strings.Contains(err.Error(), local+":2:") || calls != 0 {
				t.Fatalf("commands = %d, error = %v", calls, err)
			}
		})
	}
}

func TestPlan(t *testing.T) {
	for _, test := range []struct {
		name        string
		requirement string
		local       string
		replacement string
		goVersion   string
		want        bool
		wantErr     bool
	}{
		{name: "global applies without local file", requirement: "v0.52.0", want: true},
		{name: "local replacement wins", requirement: "v0.52.0", local: "# local override\n-replace golang.org/x/crypto=golang.org/x/crypto@v0.53.0 # retained\n"},
		{name: "versioned local replacement wins", requirement: "v0.52.0", local: "-replace=golang.org/x/crypto@v0.52.0=../crypto"},
		{name: "local requirement rejected", requirement: "v0.52.0", local: "-require=golang.org/x/crypto@v0.53.0", wantErr: true},
		{name: "unrelated local override", requirement: "v0.52.0", local: "-replace example.com/other=../other", want: true},
		{name: "equal target", requirement: "v0.56.0"},
		{name: "no downgrade", requirement: "v0.57.0"},
		{name: "newer upstream with older compiler", requirement: "v0.57.0", goVersion: "go1.25.0"},
		{name: "prerelease below target", requirement: "v0.56.0-rc.1", want: true},
		{name: "newer pseudo version", requirement: "v0.57.1-0.20261009000000-0123456789ab"},
		{name: "absent dependency"},
		{name: "upstream replacement preserved", requirement: "v0.52.0", replacement: "replace golang.org/x/crypto => ../crypto\n"},
		{name: "incompatible compiler skipped", requirement: "v0.52.0", goVersion: "go1.25.0"},
		{name: "local bypasses global Go requirement", requirement: "v0.52.0", local: "-replace golang.org/x/crypto=../crypto", goVersion: "go1.25.0"},
	} {
		t.Run(test.name, func(t *testing.T) {
			directory := t.TempDir()
			contents := "module example.com/test\n\ngo 1.22.0\n"
			if test.requirement != "" {
				contents += "require golang.org/x/crypto " + test.requirement + " // indirect\n"
			}
			writeFile(t, filepath.Join(directory, "go.mod"), contents+test.replacement)
			local := filepath.Join(directory, "go-mod-overrides")
			if test.local != "" {
				writeFile(t, local, test.local)
			}
			goVersion := test.goVersion
			if goVersion == "" {
				goVersion = "go1.26.9"
			}
			got, err := plan(testPolicy(), directory, local, goVersion, false)
			if (err != nil) != test.wantErr {
				t.Fatalf("plan error = %v", err)
			}
			var want []string
			if test.want {
				want = []string{"-replace=golang.org/x/crypto=golang.org/x/crypto@v0.56.0"}
			}
			if !reflect.DeepEqual(got, want) {
				t.Fatalf("plan = %v, want %v", got, want)
			}
		})
	}
}

func TestWorkspace(t *testing.T) {
	directory := t.TempDir()
	writeFile(t, filepath.Join(directory, "go.work"), "go 1.26.0\nuse (\n ./first\n ./second\n)\n")
	writeFile(t, filepath.Join(directory, "first/go.mod"), "module example.com/first\ngo 1.22.0\n")
	writeFile(t, filepath.Join(directory, "second/go.mod"), "module example.com/second\ngo 1.22.0\nrequire golang.org/x/crypto v0.52.0\n")
	local := filepath.Join(directory, "missing")
	got, err := plan(testPolicy(), directory, local, "go1.26.9", true)
	if err != nil || len(got) != 1 {
		t.Fatalf("workspace plan = %v, error = %v", got, err)
	}
	writeFile(t, filepath.Join(directory, "go.work"), "go 1.26.0\nuse ./second\nreplace golang.org/x/crypto => ../crypto\n")
	got, err = plan(testPolicy(), directory, local, "go1.26.9", true)
	if err != nil || len(got) != 0 {
		t.Fatalf("workspace replacement plan = %v, error = %v", got, err)
	}
}

func TestWorkspacePreservesNewerRequirement(t *testing.T) {
	for _, order := range []string{"./older\n ./newer", "./newer\n ./older"} {
		t.Run(order, func(t *testing.T) {
			directory := t.TempDir()
			writeFile(t, filepath.Join(directory, "go.work"), "go 1.26.0\nuse (\n "+order+"\n)\n")
			writeFile(t, filepath.Join(directory, "older/go.mod"), "module example.com/older\ngo 1.22.0\nrequire golang.org/x/crypto v0.52.0\n")
			writeFile(t, filepath.Join(directory, "newer/go.mod"), "module example.com/newer\ngo 1.22.0\nrequire golang.org/x/crypto v0.57.0\n")
			got, err := plan(testPolicy(), directory, filepath.Join(directory, "missing"), "go1.26.9", true)
			if err != nil || len(got) != 0 {
				t.Fatalf("workspace plan = %v, error = %v", got, err)
			}
		})
	}
}

func TestApplyOverrides(t *testing.T) {
	for _, test := range []struct {
		name      string
		local     string
		workspace bool
		vendor    bool
		want      [][]string
	}{
		{
			name:   "local applied before global with module vendoring",
			local:  "# local preference\n-replace golang.org/x/crypto=golang.org/x/crypto@v0.53.0 # keep local\n",
			vendor: true,
			want: [][]string{
				{"mod", "edit", "-replace", "golang.org/x/crypto=golang.org/x/crypto@v0.53.0"},
				{"mod", "edit", "-replace=golang.org/x/text=golang.org/x/text@v0.39.0"},
				{"mod", "tidy"},
				{"mod", "vendor"},
			},
		},
		{
			name: "missing local file still applies global",
			want: [][]string{
				{"mod", "edit", "-replace=golang.org/x/crypto=golang.org/x/crypto@v0.56.0"},
				{"mod", "edit", "-replace=golang.org/x/text=golang.org/x/text@v0.39.0"},
				{"mod", "tidy"},
			},
		},
		{
			name:      "workspace local replacement wins and skips tidy",
			local:     "-replace=golang.org/x/crypto=golang.org/x/crypto@v0.53.0\n",
			workspace: true,
			vendor:    true,
			want: [][]string{
				{"work", "edit", "-replace=golang.org/x/crypto=golang.org/x/crypto@v0.53.0"},
				{"work", "edit", "-replace=golang.org/x/text=golang.org/x/text@v0.39.0"},
				{"work", "vendor"},
			},
		},
	} {
		t.Run(test.name, func(t *testing.T) {
			directory := t.TempDir()
			moduleDir := directory
			if test.workspace {
				moduleDir = filepath.Join(directory, "module")
				writeFile(t, filepath.Join(directory, "go.work"), "go 1.22.0\nuse ./module\n")
			}
			writeFile(t, filepath.Join(moduleDir, "go.mod"), "module example.com/test\ngo 1.22.0\nrequire (\n golang.org/x/crypto v0.52.0\n golang.org/x/text v0.38.0\n)\n")
			local := filepath.Join(directory, "go-mod-overrides")
			if test.local != "" {
				writeFile(t, local, test.local)
			}
			if test.vendor {
				if err := os.Mkdir(filepath.Join(directory, "vendor"), 0o755); err != nil {
					t.Fatal(err)
				}
			}
			currentPolicy := testPolicy()
			currentPolicy.Modules["golang.org/x/text"] = modulePolicy{TargetVersion: "v0.39.0", CVEs: "CVE-2026-56852", MinimumGo: "1.25.0"}
			var calls [][]string
			err := applyOverrides(currentPolicy, directory, local, "go1.26.9", test.workspace, func(arguments ...string) error {
				calls = append(calls, arguments)
				if arguments[1] != "edit" {
					return nil
				}
				command := exec.Command("go", arguments...)
				command.Dir = directory
				workPath := "off"
				if test.workspace {
					workPath = filepath.Join(directory, "go.work")
				}
				command.Env = append(os.Environ(), "GOWORK="+workPath, "GOTOOLCHAIN=local")
				output, err := command.CombinedOutput()
				if err != nil {
					t.Fatalf("go edit: %v\n%s", err, output)
				}
				return nil
			})
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(calls, test.want) {
				t.Fatalf("commands = %v, want %v", calls, test.want)
			}
		})
	}
}

func TestApplyOverridesStopsOnFailure(t *testing.T) {
	for _, failedStep := range []string{"edit", "tidy", "vendor"} {
		t.Run(failedStep, func(t *testing.T) {
			directory := t.TempDir()
			writeFile(t, filepath.Join(directory, "go.mod"), "module example.com/test\ngo 1.22.0\n")
			local := filepath.Join(directory, "go-mod-overrides")
			writeFile(t, local, "-replace=example.com/local=../local\n")
			if err := os.Mkdir(filepath.Join(directory, "vendor"), 0o755); err != nil {
				t.Fatal(err)
			}
			failure := errors.New("command failed")
			var calls []string
			err := applyOverrides(testPolicy(), directory, local, "go1.26.9", false, func(arguments ...string) error {
				calls = append(calls, arguments[1])
				if arguments[1] == failedStep {
					return failure
				}
				return nil
			})
			if !errors.Is(err, failure) || calls[len(calls)-1] != failedStep {
				t.Fatalf("commands = %v, error = %v", calls, err)
			}
		})
	}
}

func TestApplyOverridesSkipsIncompatibleGlobal(t *testing.T) {
	directory := t.TempDir()
	writeFile(t, filepath.Join(directory, "go.mod"), "module example.com/test\ngo 1.22.0\nrequire (\n golang.org/x/crypto v0.52.0\n golang.org/x/text v0.38.0\n)\n")
	currentPolicy := testPolicy()
	currentPolicy.Modules["golang.org/x/text"] = modulePolicy{TargetVersion: "v0.39.0", CVEs: "CVE-2026-56852", MinimumGo: "1.25.0"}
	var calls [][]string
	err := applyOverrides(currentPolicy, directory, filepath.Join(directory, "missing"), "go1.25.0", false, func(arguments ...string) error {
		calls = append(calls, arguments)
		return nil
	})
	want := [][]string{
		{"mod", "edit", "-replace=golang.org/x/text=golang.org/x/text@v0.39.0"},
		{"mod", "tidy"},
	}
	if err != nil || !reflect.DeepEqual(calls, want) {
		t.Fatalf("commands = %v, error = %v", calls, err)
	}
}

func TestCommand(t *testing.T) {
	binary := filepath.Join(t.TempDir(), "go-mod-replacer")
	build := exec.Command("go", "build", "-o", binary, ".")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build: %v\n%s", err, output)
	}
	policyPath, err := filepath.Abs("../../global_overrides.json")
	if err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		name      string
		local     bool
		workspace bool
		disabled  bool
		vendor    bool
	}{
		{name: "global policy without local file"},
		{name: "positional local file and module vendor", local: true, vendor: true},
		{name: "automatically detected workspace", local: true, workspace: true, vendor: true},
		{name: "GOWORK off preserves module mode", local: true, workspace: true, disabled: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			directory := t.TempDir()
			writeFile(t, filepath.Join(directory, "go.mod"), "module example.com/test\ngo 1.22.0\n")
			writeFile(t, filepath.Join(directory, "main.go"), "package main\nfunc main() {}\n")
			if test.workspace {
				writeFile(t, filepath.Join(directory, "go.work"), "go 1.22.0\nuse .\n")
			}
			arguments := []string{"-global", policyPath}
			if test.local {
				writeFile(t, filepath.Join(directory, "local-overrides"), "# custom local file\n-replace=example.com/local=../local\n")
				arguments = append(arguments, "local-overrides")
			}
			if test.vendor {
				if err := os.Mkdir(filepath.Join(directory, "vendor"), 0o755); err != nil {
					t.Fatal(err)
				}
			}
			command := exec.Command(binary, arguments...)
			command.Dir = directory
			workPath := "off"
			if test.workspace && !test.disabled {
				workPath = filepath.Join(directory, "go.work")
			}
			command.Env = append(os.Environ(), "GOWORK="+workPath, "GOTOOLCHAIN=local", "GOPROXY=off")
			output, err := command.CombinedOutput()
			if err != nil {
				t.Fatalf("command: %v\n%s", err, output)
			}
			mode := "mod"
			if test.workspace && !test.disabled {
				mode = "work"
			}
			text := string(output)
			if test.local && !strings.Contains(text, "go "+mode+" edit -replace=example.com/local=../local") {
				t.Fatalf("local override not applied: %s", text)
			}
			if strings.Contains(text, "go mod tidy") != (mode == "mod") {
				t.Fatalf("incorrect tidy behavior: %s", text)
			}
			if test.vendor && !strings.Contains(text, "go "+mode+" vendor") {
				t.Fatalf("vendor not regenerated: %s", text)
			}
		})
	}
}
