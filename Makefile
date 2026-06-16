# Makefile for writhdeck modular build
# Concatenates source modules to generate standalone script files
#
# Usage:
#   make                                              # Build GUI with all (languages, schemes), CLI with en+fr, default+alt01
#   make LANGUAGES="fr"                               # GUI: French only (English always included)
#   make LANGUAGES="en fr de es"                      # GUI: specific languages
#   make CLI_LANGUAGES="en fr de es ko no"            # CLI: specific languages (by default: en fr)
#   make SCHEMES="default solarized gruvbox"          # GUI: specific schemes (by default: all)
#   make GUI_CONFIG=no                                # GUI: omit config dialog (~700 lines saved)
#   make CLI_SCHEMES="default alt01"                  # CLI: specific schemes (by default: default alt01)
#   make ANALYSIS_TOOLS=no                            # writhdeck.tcl/writhdeck-cli.tcl: omit analysis tools (structure, occurrences, repetitions)
#   make mini MINI_ANALYSIS_TOOLS=yes                 # writhdeck-mini.tcl: include analysis tools (off by default)
#   make jimtcl JIM_ANALYSIS_TOOLS=yes                # writhdeck-jim.tcl: include analysis tools (off by default)
#   make dos                                          # writhdeck-dos.tcl: JimTcl build with FreeDOS/NANSI.SYS display shim (see ../writhdeck-dos/NOTES.md)
#
# Typical builds:
#   make                                              # Standard: full GUI, minimal CLI
#   make mini                                         # Compact GUI-only, en, no config dialog -> writhdeck-mini.tcl
#   make LANGUAGES="en" SCHEMES="default"             # Minimal: GUI en + default scheme only
#   make CLI_LANGUAGES="en fr de es" CLI_SCHEMES="default solarized gruvbox everforest nord alt01"  # Full CLI

AVAILABLE_LANGS := $(patsubst src/i18n/%.tcl,%,$(wildcard src/i18n/*.tcl))
AVAILABLE_SCHEMES := $(patsubst src/schemes/%.tcl,%,$(wildcard src/schemes/*.tcl))
LANGUAGES ?= $(AVAILABLE_LANGS)
CLI_LANGUAGES ?= en fr
SCHEMES ?= $(AVAILABLE_SCHEMES)
CLI_SCHEMES ?= default alt01
GUI_LANGS := en $(filter-out en,$(LANGUAGES))
CLI_LANGS := en $(filter-out en,$(CLI_LANGUAGES))
GUI_I18N_FILES := $(patsubst %,src/i18n/%.tcl,$(GUI_LANGS))
CLI_I18N_FILES := $(patsubst %,src/i18n/%.tcl,$(CLI_LANGS))
GUI_SCHEME_FILES := $(patsubst %,src/schemes/%.tcl,$(SCHEMES))
CLI_SCHEME_FILES := $(patsubst %,src/schemes/%.tcl,$(CLI_SCHEMES))
SEP       := ===========================================================================

GUI_CONFIG ?= yes
GUI_CONFIG_SRC := $(if $(filter yes,$(GUI_CONFIG)),src/gui-config.tcl,)

# Analysis tools (structure outline, word occurrences, repetitions): one
# all-or-nothing module, src/analysis.tcl. On by default for writhdeck.tcl
# and writhdeck-cli.tcl; off by default for writhdeck-mini.tcl and
# writhdeck-jim.tcl. Each target has its own override variable.
ANALYSIS_TOOLS      ?= yes
MINI_ANALYSIS_TOOLS ?= no
JIM_ANALYSIS_TOOLS  ?= no
ANALYSIS_SRC      := $(if $(filter yes,$(ANALYSIS_TOOLS)),src/analysis.tcl,)
MINI_ANALYSIS_SRC := $(if $(filter yes,$(MINI_ANALYSIS_TOOLS)),src/analysis.tcl,)
JIM_ANALYSIS_SRC  := $(if $(filter yes,$(JIM_ANALYSIS_TOOLS)),src/analysis.tcl,)

GUI_SRCS  := src/state.tcl src/config.tcl $(GUI_SCHEME_FILES) src/common.tcl $(ANALYSIS_SRC) $(GUI_CONFIG_SRC) src/gui.tcl src/tui.tcl src/main.tcl
MINI_SCHEME_FILES := $(patsubst %,src/schemes/%.tcl,$(AVAILABLE_SCHEMES))
CLI_SRCS  := src/state.tcl src/config.tcl $(CLI_SCHEME_FILES) src/common.tcl $(ANALYSIS_SRC) src/tui.tcl src/main-cli.tcl
JIM_SRCS  := src/compat-jim.tcl src/state.tcl src/config.tcl $(CLI_SCHEME_FILES) src/common.tcl $(JIM_ANALYSIS_SRC) src/tui.tcl src/main-cli.tcl
DOS_SRCS  := src/compat-jim.tcl src/compat-dos.tcl src/state.tcl src/config.tcl $(CLI_SCHEME_FILES) src/common.tcl $(JIM_ANALYSIS_SRC) src/tui.tcl src/main-cli.tcl

COMPACT_SCRIPT := tools/tcl-compact.tcl

.PHONY: all mini clean compact compact-cli jimtcl dos sfx .FORCE

JIMSH ?= /opt/jimsh

all: writhdeck.tcl writhdeck-cli.tcl writhdeck-mini.tcl

writhdeck.tcl: src/boot.tcl $(GUI_SRCS) $(GUI_I18N_FILES) Makefile
	@rm -f $@
	@cat src/boot.tcl > $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "state.tcl" "$(SEP)" >> $@
	@cat src/state.tcl >> $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "config.tcl" "$(SEP)" >> $@
	@cat src/config.tcl >> $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "schemes ($(SCHEMES))" "$(SEP)" >> $@
	@for f in $(GUI_SCHEME_FILES); do cat $$f >> $@; done
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "i18n ($(LANGUAGES))" "$(SEP)" >> $@
	@for f in $(GUI_I18N_FILES); do cat $$f >> $@; done
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "common.tcl" "$(SEP)" >> $@
	@cat src/common.tcl >> $@
	@for f in $(ANALYSIS_SRC); do printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "analysis.tcl" "$(SEP)" >> $@; cat $$f >> $@; done
	@for f in $(GUI_CONFIG_SRC); do printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "gui-config.tcl" "$(SEP)" >> $@; cat $$f >> $@; done
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "gui.tcl" "$(SEP)" >> $@
	@cat src/gui.tcl >> $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "tui.tcl" "$(SEP)" >> $@
	@cat src/tui.tcl >> $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "main.tcl" "$(SEP)" >> $@
	@cat src/main.tcl >> $@
	@chmod +x $@
	@echo "Built $@ (GUI+TUI, languages: $(GUI_LANGS), schemes: $(SCHEMES)$(if $(GUI_CONFIG_SRC),, no-config))"

writhdeck-cli.tcl: src/boot-cli.tcl $(CLI_SRCS) $(CLI_I18N_FILES) Makefile
	@rm -f $@
	@cat src/boot-cli.tcl > $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "state.tcl" "$(SEP)" >> $@
	@cat src/state.tcl >> $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "config.tcl" "$(SEP)" >> $@
	@cat src/config.tcl >> $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "schemes ($(CLI_SCHEMES))" "$(SEP)" >> $@
	@for f in $(CLI_SCHEME_FILES); do cat $$f >> $@; done
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "i18n ($(CLI_LANGUAGES))" "$(SEP)" >> $@
	@for f in $(CLI_I18N_FILES); do cat $$f >> $@; done
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "common.tcl" "$(SEP)" >> $@
	@cat src/common.tcl >> $@
	@for f in $(ANALYSIS_SRC); do printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "analysis.tcl" "$(SEP)" >> $@; cat $$f >> $@; done
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "tui.tcl" "$(SEP)" >> $@
	@cat src/tui.tcl >> $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "main-cli.tcl" "$(SEP)" >> $@
	@cat src/main-cli.tcl >> $@
	@chmod +x $@
	@echo "Built $@ (TUI-only, languages: $(CLI_LANGS), schemes: $(CLI_SCHEMES))"

sfx: writhdeck-jim.tcl
	python3 tools/make-sfx.py $(JIMSH) writhdeck-jim.tcl writhdeck-sfx

jimtcl: writhdeck-jim.tcl

writhdeck-jim.tcl: src/boot-jim.tcl $(JIM_SRCS) $(CLI_I18N_FILES) Makefile
	@rm -f $@
	@cat src/boot-jim.tcl > $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "compat-jim.tcl" "$(SEP)" >> $@
	@cat src/compat-jim.tcl >> $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "state.tcl" "$(SEP)" >> $@
	@cat src/state.tcl >> $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "config.tcl" "$(SEP)" >> $@
	@cat src/config.tcl >> $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "schemes ($(CLI_SCHEMES))" "$(SEP)" >> $@
	@for f in $(CLI_SCHEME_FILES); do cat $$f >> $@; done
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "i18n ($(CLI_LANGUAGES))" "$(SEP)" >> $@
	@for f in $(CLI_I18N_FILES); do cat $$f >> $@; done
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "common.tcl" "$(SEP)" >> $@
	@cat src/common.tcl >> $@
	@for f in $(JIM_ANALYSIS_SRC); do printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "analysis.tcl" "$(SEP)" >> $@; cat $$f >> $@; done
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "tui.tcl" "$(SEP)" >> $@
	@cat src/tui.tcl >> $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "main-cli.tcl" "$(SEP)" >> $@
	@cat src/main-cli.tcl >> $@
	@chmod +x $@
	@echo "Built $@ (JimTcl TUI-only, languages: $(CLI_LANGS), schemes: $(CLI_SCHEMES))"

dos: writhdeck-dos.tcl

writhdeck-dos.tcl: src/boot-jim.tcl $(DOS_SRCS) $(CLI_I18N_FILES) Makefile
	@rm -f $@
	@cat src/boot-jim.tcl > $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "compat-jim.tcl" "$(SEP)" >> $@
	@cat src/compat-jim.tcl >> $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "compat-dos.tcl" "$(SEP)" >> $@
	@cat src/compat-dos.tcl >> $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "state.tcl" "$(SEP)" >> $@
	@cat src/state.tcl >> $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "config.tcl" "$(SEP)" >> $@
	@cat src/config.tcl >> $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "schemes ($(CLI_SCHEMES))" "$(SEP)" >> $@
	@for f in $(CLI_SCHEME_FILES); do cat $$f >> $@; done
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "i18n ($(CLI_LANGUAGES))" "$(SEP)" >> $@
	@for f in $(CLI_I18N_FILES); do cat $$f >> $@; done
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "common.tcl" "$(SEP)" >> $@
	@cat src/common.tcl >> $@
	@for f in $(JIM_ANALYSIS_SRC); do printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "analysis.tcl" "$(SEP)" >> $@; cat $$f >> $@; done
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "tui.tcl" "$(SEP)" >> $@
	@cat src/tui.tcl >> $@
	@printf '\n# %s\n# %s\n# %s\n' "$(SEP)" "main-cli.tcl" "$(SEP)" >> $@
	@cat src/main-cli.tcl >> $@
	@chmod +x $@
	@echo "Built $@ (FreeDOS/JimTcl TUI-only, languages: $(CLI_LANGS), schemes: $(CLI_SCHEMES))"

compact: writhdeck.tcl writhdeck-cli.tcl
	@tclsh $(COMPACT_SCRIPT) writhdeck.tcl writhdeck-compact.tcl
	@chmod +x writhdeck-compact.tcl
	@tclsh $(COMPACT_SCRIPT) writhdeck-cli.tcl writhdeck-cli-compact.tcl
	@chmod +x writhdeck-cli-compact.tcl

compact-cli: writhdeck-cli.tcl
	@tclsh $(COMPACT_SCRIPT) writhdeck-cli.tcl writhdeck-cli-compact.tcl
	@chmod +x writhdeck-cli-compact.tcl

mini: writhdeck-mini.tcl

writhdeck-mini.tcl: src/boot.tcl src/state.tcl src/config.tcl $(MINI_SCHEME_FILES) \
                    src/i18n/en.tcl src/common.tcl $(MINI_ANALYSIS_SRC) src/gui.tcl src/tui.tcl src/main.tcl \
                    $(COMPACT_SCRIPT) Makefile
	@rm -f writhdeck-mini.tcl writhdeck-mini-raw.tcl
	@cat src/boot.tcl src/state.tcl src/config.tcl > writhdeck-mini-raw.tcl
	@for f in $(MINI_SCHEME_FILES); do cat $$f >> writhdeck-mini-raw.tcl; done
	@cat src/i18n/en.tcl src/common.tcl >> writhdeck-mini-raw.tcl
	@for f in $(MINI_ANALYSIS_SRC); do cat $$f >> writhdeck-mini-raw.tcl; done
	@cat src/gui.tcl src/tui.tcl src/main.tcl >> writhdeck-mini-raw.tcl
	@tclsh $(COMPACT_SCRIPT) writhdeck-mini-raw.tcl writhdeck-mini.tcl
	@rm writhdeck-mini-raw.tcl
	@chmod +x writhdeck-mini.tcl
	@echo "Built writhdeck-mini.tcl (GUI+TUI compact, en only, no config dialog$(if $(MINI_ANALYSIS_SRC), + analysis tools,))"

clean:
	rm -f writhdeck.tcl writhdeck-cli.tcl writhdeck-compact.tcl writhdeck-cli-compact.tcl writhdeck-jim.tcl writhdeck-dos.tcl writhdeck-sfx writhdeck-mini.tcl writhdeck-mini-raw.tcl
	@echo "Cleaned build artifacts"

.PHONY: test-gui test-cli test test-i18n test-syntax test-langs lint-doc

test-gui: writhdeck.tcl
	@echo "Testing writhdeck.tcl (GUI mode)..."
	@wish writhdeck.tcl --help > /dev/null && echo "✓ GUI version loads"

test-cli: writhdeck-cli.tcl
	@echo "Testing writhdeck-cli.tcl (TUI mode)..."
	@tclsh writhdeck-cli.tcl --help > /dev/null && echo "✓ CLI version loads"

test-i18n:
	@echo "Testing i18n translations..."
	@tclsh tests/test-i18n.tcl

test-syntax:
	@echo "Checking Tcl syntax..."
	@tclsh tests/test-syntax.tcl

test-langs:
	@echo "Testing builds with different language combinations..."
	@$(MAKE) clean > /dev/null && $(MAKE) LANGUAGES="fr" > /dev/null && echo "✓ LANGUAGES=fr (includes en automatically)"
	@$(MAKE) clean > /dev/null && $(MAKE) LANGUAGES="de es" > /dev/null && echo "✓ LANGUAGES=de es"
	@$(MAKE) clean > /dev/null && $(MAKE) > /dev/null && echo "✓ Default build (all languages)"

test: test-i18n test-syntax test-gui test-cli test-langs
	@echo ""
	@echo "✓ All regression tests passed"

lint-doc:
	@echo "Aligning markdown table pipes..."
	@tclsh tools/align-tables.tcl writhdeck_MANUAL.md --inplace
	@tclsh tools/align-tables.tcl README.md --inplace
	@tclsh tools/align-tables.tcl README.fr.md --inplace
	@tclsh tools/align-tables.tcl CLAUDE.md --inplace
	@echo "✓ Documentation tables aligned"
