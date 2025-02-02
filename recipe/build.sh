#!/bin/bash

set -ex

if [[ "$target_platform" == "linux-ppc64le" ]]; then
  # avoid error 'relocation truncated to fit: R_PPC64_REL24'
  export CFLAGS="$(echo ${CFLAGS} | sed 's/-fno-plt//g') -fplt"
  export CXXFLAGS="$(echo ${CXXFLAGS} | sed 's/-fno-plt//g') -fplt"
fi

# Make rpcgen use C Pre Processor provided by the Conda ecosystem. The
# rpcgen binary assumes that the corresponding binary is always 'cpp'.
_rpcgen_hack_dir=$SRC_DIR/rpcgen_hack

if [[ "${target_platform}" == *"linux"* ]]; then
    ## We don't have a conda package for rpcgen, but it is present in the
    ## compiler sysroot on Linux. However, the value of PT_INTERP is not
    ## convenient for executing it. ('lib' instead of 'lib64')
    _target_sysroot=$(${CXX_FOR_BUILD:-$CC} --print-sysroot)
    _target_rpcgen_bin=${_target_sysroot}/usr/bin/rpcgen
    _target_interpreter=${_target_sysroot}/$(patchelf --print-interpreter ${_target_rpcgen_bin})
    _target_libdir=$(dirname ${_target_interpreter})

    ## Generate a wrapper which will use the interpreter provided in the
    ## compiler sysroot to exec rpcgen and also provide the appropriate
    ## /path/to/dir containing the C Pre Processor (cpp) binary.
    mkdir -p $_rpcgen_hack_dir/bin
    cat <<EOF > ${_rpcgen_hack_dir}/bin/rpcgen
#!/bin/bash
${_target_interpreter} --library-path ${_target_libdir} ${_target_rpcgen_bin} -Y ${_rpcgen_hack_dir}/bin \$@
EOF
    ln -sf $(readlink -f ${CPP}) ${_rpcgen_hack_dir}/bin/cpp
    chmod +x ${_rpcgen_hack_dir}/bin/{rpcgen,cpp}

elif [[ "${target_platform}" == *"osx"* ]]; then
    ## Unlink GNU Compilers, Clang doesn't provide a separate binary
    ## for pre processing. So we trick rpcgen to use our Clang instead.
    mkdir -p $_rpcgen_hack_dir/bin
    cat <<EOF > ${_rpcgen_hack_dir}/bin/rpcgen
#!/bin/bash
rpcgen -Y ${_rpcgen_hack_dir}/bin \$@
EOF
    ln -sf $BUILD_PREFIX/bin/$(basename ${CC}) ${_rpcgen_hack_dir}/bin/cpp
    chmod +x ${_rpcgen_hack_dir}/bin/{rpcgen,cpp}
fi

declare -a _xtra_cmake_args
if [[ $target_platform == osx-64 ]]; then
    _xtra_cmake_args+=(-DWITH_ROUTER=OFF)
    export CXXFLAGS="${CXXFLAGS:-} -D_LIBCPP_DISABLE_AVAILABILITY=1"
fi

if [[ $target_platform == osx-arm64 ]] && [[ $CONDA_BUILD_CROSS_COMPILATION == 1 ]]; then
    # Build all intermediate codegen binaries for the build platform
    # xref: https://cmake.org/pipermail/cmake/2013-January/053252.html
    export OPENSSL_ROOT_DIR=$BUILD_PREFIX
    echo "#### Cross-compiling some binaries for osx-64"
    env -u SDKROOT -u CONDA_BUILD_SYSROOT -u CMAKE_PREFIX_PATH \
        -u CXXFLAGS -u CPPFLAGS -u CFLAGS -u LDFLAGS \
        cmake -S$SRC_DIR -Bbuild.codegen -GNinja \
            -DWITH_ICU=system \
            -DWITH_ZLIB=system \
            -DWITH_ZSTD=system \
            -DWITH_PROTOBUF=system \
            -DCMAKE_PREFIX_PATH=$BUILD_PREFIX \
            -DCMAKE_C_COMPILER=$CC_FOR_BUILD \
            -DCMAKE_CXX_COMPILER=$CXX_FOR_BUILD \
            -DPROTOBUF_INCLUDE_DIR=${BUILD_PREFIX}/include \
            -DProtobuf_PROTOC_EXECUTABLE=$BUILD_PREFIX/bin/protoc \
            -DCMAKE_CXX_FLAGS="-isystem $BUILD_PREFIX/include" \
            -DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath,$BUILD_PREFIX/lib -L$BUILD_PREFIX/lib"
    cmake --build build.codegen -- \
        xprotocol_plugin comp_err comp_sql gen_lex_hash libmysql_api_test \
        json_schema_embedder gen_lex_token gen_keyword_list comp_client_err \
        cno_huffman_generator

    # Put the codegen binaries in $PATH
    export PATH=$SRC_DIR/build.codegen/runtime_output_directory:$PATH
    export PATH=$SRC_DIR/build.codegen/router/src/json_schema_embedder:$PATH

    # Tell CMake about our cross toolchains
    _xtra_cmake_args+=(${CMAKE_ARGS})

    # The MySQL CMake files use TRY_RUN/CHECK_C_SOURCE_RUNS to inspect certain
    # properties about the build environment. Since we are cross compiling, we
    # cannot run these executables (which target the host platform) on the
    # build platform, so we tell CMake about their results explicitly:

    ## 11.1 SDK does support CLOCK_GETTIME with CLOCK_MONOTONIC and CLOCK_REALTIME as arguments
    _xtra_cmake_args+=(-DHAVE_CLOCK_GETTIME_EXITCODE=0)
    _xtra_cmake_args+=(-DHAVE_CLOCK_REALTIME_EXITCODE=0)

    ## Tell the build system that our cross compiler version is sufficient for the build
    _xtra_cmake_args+=(-DHAVE_SUPPORTED_CLANG_VERSION_EXITCODE=0)

    ## Use the protoc from the build platform as it needs to be exec'd
    _xtra_cmake_args+=(-DPROTOBUF_PROTOC_EXECUTABLE=$BUILD_PREFIX/bin/protoc)

    # Copied from the osx-64 build
    _xtra_cmake_args+=(-DHAVE___BUILTIN_FFS=1)
fi


cmake -S$SRC_DIR -Bbuild -GNinja \
  -DCMAKE_CXX_STANDARD=20 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="${_rpcgen_hack_dir};$PREFIX" \
  -DCOMPILATION_COMMENT=conda-forge \
  -DCMAKE_FIND_FRAMEWORK=LAST \
  -DOPENSSL_ROOT_DIR=$PREFIX \
  -DPKG_CONFIG_EXECUTABLE=${BUILD_PREFIX}/bin/pkg-config \
  -DWITH_UNIT_TESTS=OFF \
  -DWITH_ZLIB=system \
  -DWITH_ZSTD=system \
  -DWITH_LZ4=system \
  -DWITH_ICU=system \
  -DWITH_EDITLINE=system \
  -DWITH_PROTOBUF=system \
  -DWITH_KERBEROS=none \
  -DWITH_FIDO=none \
  -DWITH_SASL=none \
  -DPROTOBUF_INCLUDE_DIR=${PREFIX}/include \
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
  -DWITH_AUTHENTICATION_CLIENT_PLUGINS=ON \
  "${_xtra_cmake_args[@]}"

if [[ $target_platform == osx-arm64 ]] && [[ $CONDA_BUILD_CROSS_COMPILATION == 1 ]]; then
    # Update the /path/to/xprotocol_plugin to the one built for the build platform
    sed -i.bak "s,\(--plugin=protoc-gen-yplg=\)[^ ]*,\1$SRC_DIR/build.codegen/runtime_output_directory/xprotocol_plugin,g" build/build.ninja
fi

export NINJA_STATUS="[%f+%r/%t] "

cmake --build build
