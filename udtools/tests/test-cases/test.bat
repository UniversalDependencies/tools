@echo off
REM Test the UD validator on a set of short CoNLL-U files.
REM The log file is versioned, so we can check git diff and see if it is OK.
REM Usage: tools\validator\tests\test-cases\test.bat 2> tools\validator\tests\test-cases\test.log
SET "SCRIPT_DIR=%~dp0"
for %%f in ("%SCRIPT_DIR%invalid-level1\*.conllu") do (
    @echo -------------------------------------------------------------------------------- 1>&2
    @echo %%f
    @echo Processing file: %%f 1>&2
    python %SCRIPT_DIR%..\..\..\validate.py --level 1 --lang ud "%%f"
    @echo. 1>&2
)
@echo -------------------------------------------------------------------------------- 1>&2
@echo --------------------------------------------------------------------------------
@echo LEVEL 2 TESTS 1>&2
for %%f in ("%SCRIPT_DIR%invalid-level2\*.conllu") do (
    @echo -------------------------------------------------------------------------------- 1>&2
    @echo %%f
    @echo Processing file: %%f 1>&2
    python %SCRIPT_DIR%..\..\..\validate.py --level 2 --lang ud "%%f"
    @echo. 1>&2
)
@echo -------------------------------------------------------------------------------- 1>&2
@echo --------------------------------------------------------------------------------
@echo LEVEL 3 TESTS 1>&2
for %%f in ("%SCRIPT_DIR%invalid-level3\*.conllu") do (
    @echo -------------------------------------------------------------------------------- 1>&2
    @echo %%f
    @echo Processing file: %%f 1>&2
    python %SCRIPT_DIR%..\..\..\validate.py --level 3 --lang ud "%%f"
    @echo. 1>&2
)
@echo -------------------------------------------------------------------------------- 1>&2
@echo --------------------------------------------------------------------------------
@echo LEVEL 4-5 TESTS 1>&2
for %%f in ("%SCRIPT_DIR%invalid-level4-5\cs_*.conllu") do (
    @echo -------------------------------------------------------------------------------- 1>&2
    @echo %%f
    @echo Processing file: %%f 1>&2
    python %SCRIPT_DIR%..\..\..\validate.py --level 5 --lang cs "%%f"
    @echo. 1>&2
)
for %%f in ("%SCRIPT_DIR%invalid-level4-5\yrl_*.conllu") do (
    @echo -------------------------------------------------------------------------------- 1>&2
    @echo %%f
    @echo Processing file: %%f 1>&2
    python %SCRIPT_DIR%..\..\..\validate.py --level 5 --lang yrl "%%f"
    @echo. 1>&2
)
@echo -------------------------------------------------------------------------------- 1>&2
@echo --------------------------------------------------------------------------------
@echo THE FOLLOWING FILES SHOULD BE VALID 1>&2
for %%f in ("%SCRIPT_DIR%valid\*.conllu") do (
    @echo -------------------------------------------------------------------------------- 1>&2
    @echo %%f
    @echo Processing file: %%f 1>&2
    python %SCRIPT_DIR%..\..\..\validate.py --level 3 --lang ud "%%f"
    @echo. 1>&2
)
