#!/bin/bash
set -x

_rpcgen_hack_dir=""
if [[ "${target_platform}" == *"linux"* ]]; then
    _rpcgen_hack_dir=$SRC_DIR/rpcgen_hack
    _target_sysroot=$($CXX --print-sysroot)
    _target_rpcgen_bin=${_target_sysroot}/usr/bin/rpcgen
    _target_interpreter=${_target_sysroot}/$(patchelf --print-interpreter ${_target_rpcgen_bin})
    _target_libdir=${_target_sysroot}/$(dirname ${_target_interpreter})
    mkdir -p $_rpcgen_hack_dir/bin
    cat <<EOF > ${_rpcgen_hack_dir}/bin/rpcgen
#!/bin/bash
${_target_interpreter} --library-path ${_target_libdir} ${_target_rpcgen_bin} -Y ${_rpcgen_hack_dir}/bin \$@
EOF
    ln -s $(readlink -f ${CPP}) ${_rpcgen_hack_dir}/bin/cpp
    chmod +x ${_rpcgen_hack_dir}/bin/{rpcgen,cpp}
fi

declare -a _xtra_cmake_args
if [[ $target_platform == osx-64 ]]; then
    _xtra_cmake_args+=(-DWITH_ROUTER=OFF)
    export CXXFLAGS="${CXXFLAGS:-} -D_LIBCPP_DISABLE_AVAILABILITY=1"
fi
export CXXFLAGS="${CXXFLAGS:-} -fno-pie"

cmake ${CMAKE_ARGS} -S$SRC_DIR -Bbuild -GNinja \
  -DCMAKE_CXX_STANDARD=14 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="${_rpcgen_hack_dir};$PREFIX" \
  -DCOMPILATION_COMMENT=conda-forge \
  -DCMAKE_FIND_FRAMEWORK=LAST \
  -DWITH_UNIT_TESTS=OFF \
  -DWITH_SASL=system \
  -DWITH_ZLIB=system \
  -DWITH_ZSTD=system \
  -DWITH_LZ4=system \
  -DWITH_ICU=system \
  -DWITH_EDITLINE=system \
  -DWITH_PROTOBUF=system \
  -DWITH_LIBEVENT=system \
  -DWITH_BOOST=$SRC_DIR/boost \
  -DDEFAULT_CHARSET=utf8 \
  -DDEFAULT_COLLATION=utf8_general_ci \
  -DINSTALL_INCLUDEDIR=include/mysql \
  -DINSTALL_MANDIR=share/man \
  -DINSTALL_DOCDIR=share/doc/mysql \
  -DINSTALL_DOCREADMEDIR=mysql \
  -DINSTALL_INFODIR=share/info \
  -DCMAKE_INSTALL_PREFIX=$PREFIX \
  -DINSTALL_MYSQLSHAREDIR=share/mysql \
  -DINSTALL_SUPPORTFILESDIR=mysql/support-files \
  "${_xtra_cmake_args[@]}"

# PPC64le fails with too many jobs
MAX_JOBS=4
CPU_COUNT=$(( CPU_COUNT < MAX_JOBS ? CPU_COUNT : MAX_JOBS ))
cmake --build build --parallel ${CPU_COUNT}
