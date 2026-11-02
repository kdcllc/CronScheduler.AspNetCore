@echo off
setlocal
set "AK_BASH="
set "S=%~dpn0.sh"
set "S=%S:\=/%"

set "OV="
if defined AGENT_KIT_BASH set "OV=%AGENT_KIT_BASH:"=%"
if defined OV call :TryCandidate "%OV%"
if defined AK_BASH goto :Run

set "OV="
if defined CLAUDE_CODE_GIT_BASH_PATH set "OV=%CLAUDE_CODE_GIT_BASH_PATH:"=%"
if defined OV call :TryCandidate "%OV%"
if defined AK_BASH goto :Run

set "GIT_EXEC="
for /f "delims=" %%G in ('git --exec-path 2^>nul') do set "GIT_EXEC=%%G"
if not defined GIT_EXEC goto :AfterGit
set "P=%GIT_EXEC:/=\%"
for %%I in ("%P%\..\..\..") do set "CAND=%%~fI\bin\bash.exe"
call :TryCandidate "%CAND%"
if defined AK_BASH goto :Run
:AfterGit

call :TryCandidate "%ProgramFiles%\Git\bin\bash.exe"
if defined AK_BASH goto :Run

call :TryCandidate "%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if defined AK_BASH goto :Run

>&2 echo agent-kit: Git Bash not found - install Git for Windows from https://git-scm.com/download/win or set AGENT_KIT_BASH to the full path of bash.exe.
exit /b 127

:Run
"%AK_BASH%" "%S%" %*
exit /b

:TryCandidate
set "CAND=%~1"
if not defined CAND exit /b 1
set "CAND=%CAND:"=%"
if not defined CAND exit /b 1
for %%I in ("%CAND%") do set "CAND=%%~fI"
if not exist "%CAND%" exit /b 1
if exist "%CAND%\" exit /b 1
call :IsWslStub "%CAND%"
if not errorlevel 1 exit /b 1
set "AK_BASH=%CAND%"
exit /b 0

:IsWslStub
set "P=%~1"
if /i "%P%"=="%SystemRoot%\System32\bash.exe" exit /b 0
if /i "%P:~-31%"=="\Microsoft\WindowsApps\bash.exe" exit /b 0
exit /b 1
