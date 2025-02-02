@echo on

if exist %LIBRARY_LIB%\event_openssl.lib (
  set "libevent_openssl_lib=%LIBRARY_LIB%\event_openssl.lib"
) else (
  set "libevent_openssl_lib=%LIBRARY_LIB%\event.lib"
)

if exist %LIBRARY_LIB%\liblz4.lib (
  set "lz4_lib=%LIBRARY_LIB%\liblz4.lib"
) else (
  set "lz4_lib=%LIBRARY_LIB%\lz4.lib"
)

set "OPENSSL_ROOT_DIR=%LIBRARY_PREFIX%"

cmake -S%SRC_DIR% -Bbuild -GNinja ^
  -DCMAKE_CXX_STANDARD=20 ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DFORCE_UNSUPPORTED_COMPILER=1 ^
  -DCMAKE_PREFIX_PATH=%LIBRARY_PREFIX% ^
  -DCOMPILATION_COMMENT=conda-forge ^
  -DWITH_UNIT_TESTS=OFF ^
  -DWITH_ZLIB=system ^
  -DWITH_ZSTD=system ^
  -DWITH_LZ4=system ^
  -DLZ4_SYSTEM_LIBRARY=%lz4_lib% ^
  -DLIBEVENT_OPENSSL=%libevent_openssl_lib% ^
  -DWITH_ICU=system ^
  -DWITH_PROTOBUF=system ^
  -DWITH_KERBEROS=none ^
  -DWITH_FIDO=none ^
  -DWITH_SASL=none ^
  -DPROTOBUF_INCLUDE_DIR=%LIBRARY_PREFIX%\include ^
  -DDEFAULT_CHARSET=utf8 ^
  -DDEFAULT_COLLATION=utf8_general_ci ^
  -DINSTALL_INCLUDEDIR=include/mysql ^
  -DINSTALL_MANDIR=share/man ^
  -DINSTALL_DOCDIR=share/doc/mysql ^
  -DINSTALL_DOCREADMEDIR=mysql ^
  -DINSTALL_INFODIR=share/info ^
  -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
  -DINSTALL_MYSQLSHAREDIR=share/mysql ^
  -DINSTALL_SUPPORTFILESDIR=mysql/support-files ^
  -DWITH_AUTHENTICATION_CLIENT_PLUGINS=ON
if %ERRORLEVEL% neq 0 exit 1

cmake --build build --config Release
if %ERRORLEVEL% neq 0 exit 1
