@echo off
setlocal

REM ============================================
REM Configurações
REM ============================================
set "ONEDRIVE=C:\onedrive\OneDrive - Sicoob"

echo ============================================
echo Iniciando backup para o OneDrive...
echo ============================================

REM ============================================
REM Atualiza o repositório gesin2
REM ============================================
echo.
echo Executando git pull em C:\ambiente\gesin2...

pushd "C:\ambiente\gesin2"

git pull

if errorlevel 1 (
    echo.
    echo ERRO: Falha ao executar git pull.
    popd
    pause
    exit /b 1
)

popd

REM ============================================
REM integracao-credito-legado
REM ============================================
echo.
echo Sincronizando integracao-credito-legado...

robocopy ^
"C:\ambiente\integracao-credito-legado" ^
"%ONEDRIVE%\integracao-credito-legado" ^
/MIR /FFT /R:2 /W:2 ^
/XD ".git" "target"

REM ============================================
REM gesin2 - somente arquivos SQL
REM ============================================
echo.
echo Sincronizando SQLs do gesin2...

robocopy ^
"C:\ambiente\gesin2\Financiamento" ^
"%ONEDRIVE%\gesin2" ^
*.sql ^
/MIR /FFT /R:2 /W:2

REM ============================================
REM chamados
REM ============================================
echo.
echo Sincronizando chamados...

robocopy ^
"C:\chamados" ^
"%ONEDRIVE%\chamados" ^
/MIR /FFT /R:2 /W:2

REM ============================================
REM mkd-manual
REM ============================================
echo.
echo Sincronizando mkd-manual...

robocopy ^
"C:\mkd-manual" ^
"%ONEDRIVE%\mkd-manual" ^
/MIR /FFT /R:2 /W:2

echo.
echo ============================================
echo Backup concluído com sucesso.
echo ============================================

endlocal
pause