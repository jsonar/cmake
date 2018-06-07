include(ExternalProject)
include(GNUInstallDirs)
string(REGEX MATCH "^lib(64)?" EXTERNAL_INSTALL_LIBDIR ${CMAKE_INSTALL_LIBDIR})
if(EXTERNAL_INSTALL_LIBDIR STREQUAL lib64)
  set(LIBSUFF 64)
endif()

macro(sonar_external_project_dirs project)
  # set variables project_<dir> for each of the requested properties
  # Usage:
  #  sonar_external_project_dirs myproject install_dir source_dir...
  #
  #  will create variables myproject_install_dir, myproject_source_dir,...
  #
  string(REPLACE - _ project_var ${project})
  foreach(prop ${ARGN})
    ExternalProject_Get_Property(${project} ${prop})
    set(${project_var}_${prop} ${${prop}})
    set(${project_var}_${prop} ${${prop}} PARENT_SCOPE)
  endforeach()
endmacro()

function(target_include_external_directory target external property dir)
  ExternalProject_Get_Property(${external} ${property})
  set(include_dir ${${property}}/${dir})
  execute_process(COMMAND ${CMAKE_COMMAND} -E make_directory ${include_dir})
  set_property(TARGET ${target}
    PROPERTY INTERFACE_INCLUDE_DIRECTORIES ${include_dir} APPEND)
endfunction()

function(build_openssl)
  cmake_parse_arguments(OPENSSL "" "VERSION" "" ${ARGN})
  if(TARGET openssl)
    sonar_external_project_dirs(openssl install_dir)
    return()
  endif()
  if(NOT OPENSSL_VERSION)
    set(OPENSSL_VERSION 1.0.2o)
  endif()
  message(STATUS "Building openssl-${OPENSSL_VERSION}")
  if(CMAKE_BUILD_TYPE STREQUAL Debug)
    set(build_flags
      -d
      no-asm
      -g3
      -O0
      -fno-omit-frame-pointer
      -fno-inline-functions
      # The following helps avoid valgrind errors, but might affect correctness (I don't know)
      # -DPURIFY
      )
  endif()
  ExternalProject_Add(openssl
    URL https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ./config
      ${build_flags}
      --openssldir=<INSTALL_DIR>
      --prefix=<INSTALL_DIR>
      -fPIC
      no-shared
    BUILD_BYPRODUCTS
      <INSTALL_DIR>/lib/libssl.a
      <INSTALL_DIR>/lib/libcrypto.a
      )
  sonar_external_project_dirs(openssl install_dir)
  add_library(openssl::ssl STATIC IMPORTED GLOBAL)
  add_dependencies(openssl::ssl openssl)
  set_target_properties(openssl::ssl PROPERTIES
    IMPORTED_LOCATION ${openssl_install_dir}/lib/libssl.a)
  target_include_external_directory(openssl::ssl openssl install_dir include)

  add_library(openssl::crypto STATIC IMPORTED GLOBAL)
  add_dependencies(openssl::crypto openssl)
  set_target_properties(openssl::crypto PROPERTIES
    IMPORTED_LOCATION ${openssl_install_dir}/lib/libcrypto.a)
  target_include_external_directory(openssl::crypto openssl install_dir include)
  find_package(ZLIB)
  set_property(TARGET openssl::crypto
    PROPERTY
      INTERFACE_LINK_LIBRARIES
        ${CMAKE_DL_LIBS}
        ZLIB::ZLIB
    )
endfunction()

function(build_mongoc)
  # builds mongoc as an external project. Provides
  # targets mongo::lib and bson::lib
  cmake_parse_arguments(MONGOC "" "VERSION" "" ${ARGN})
  message(STATUS "Building mongo-c-driver-${MONGOC_VERSION}")
  build_openssl()
  ExternalProject_Add(mongoc
    URL https://github.com/mongodb/mongo-c-driver/releases/download/${MONGOC_VERSION}/mongo-c-driver-${MONGOC_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    DEPENDS openssl
    CONFIGURE_COMMAND PKG_CONFIG_PATH=${openssl_install_dir}/lib/pkgconfig <SOURCE_DIR>/configure
      --disable-automatic-init-and-cleanup
      --with-libbson=bundled
      --enable-static
      --disable-shared
      --disable-sasl
      --disable-examples
      --disable-man-pages
      --disable-tests
      $<$<CONFIG:Debug>:--enable-debug>
      --prefix <INSTALL_DIR>
    BUILD_BYPRODUCTS
      <INSTALL_DIR>/lib/libmongoc-1.0.a
      <INSTALL_DIR>/lib/libbson-1.0.a
      )
  sonar_external_project_dirs(mongoc binary_dir source_dir install_dir)
  foreach(driver mongo bson)
    set(lib ${driver}::lib)
    set(header ${driver}::header-only)
    if(driver STREQUAL mongo)
      # annoying inconsistency in library naming...
      set(libname libmongoc-1.0)
    else()
      set(libname libbson-1.0)
    endif()
    set(archive lib/${libname}.a)
    set(include include/${libname})
    add_library(${lib} STATIC IMPORTED GLOBAL)
    add_dependencies(${lib} mongoc)
    set_property(TARGET ${lib} PROPERTY
      IMPORTED_LOCATION ${mongoc_install_dir}/${archive})
    target_include_external_directory(${lib} mongoc install_dir ${include})

    add_library(${header} INTERFACE IMPORTED)
    add_dependencies(${header} mongoc)
    target_include_external_directory(${header} mongoc install_dir ${include})

  endforeach()
  # mongoc requires openssl, rt and bson::lib
  find_package(Threads REQUIRED)
  find_library(rt rt)
  set_property(TARGET mongo::lib
    PROPERTY
    INTERFACE_LINK_LIBRARIES
      openssl::ssl
      ${rt}
      bson::lib
      openssl::crypto
      Threads::Threads
    APPEND
    )
  if(MONGOC_VERSION VERSION_GREATER_EQUAL 1.7.0)
    set_property(TARGET mongo::lib
      PROPERTY
      INTERFACE_LINK_LIBRARIES
        resolv
        z
        snappy
      APPEND
      )
  endif()
  set_property(TARGET mongo::header-only
    PROPERTY INTERFACE_LINK_LIBRARIES
      bson::header-only
    )
endfunction()

function(build_libssh2)
  if(TARGET libssh2)
    sonar_external_project_dirs(libssh2 install_dir)
    return()
  endif()
  cmake_parse_arguments(LIBSSH2 "" "VERSION" "" ${ARGN})
  if(NOT LIBSSH2_VERSION)
    set(LIBSSH2_VERSION 1.8.0)
  endif()
  build_openssl()
  message(STATUS "Building libssh2-${LIBSSH2_VERSION}")
  ExternalProject_Add(libssh2
    URL https://www.libssh2.org/download/libssh2-${LIBSSH2_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    DEPENDS openssl
    CMAKE_ARGS
      -DBUILD_EXAMPLES=OFF
      -DBUILD_SHARED_LIBS=OFF
      -DBUILD_TESTING=OFF
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_MESSAGE=LAZY
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON
      -DCMAKE_PREFIX_PATH=${openssl_install_dir}
      -DCRYPTO_BACKEND=OpenSSL
      -DENABLE_ZLIB_COMPRESSION=ON
    BUILD_BYPRODUCTS <INSTALL_DIR>/${EXTERNAL_INSTALL_LIBDIR}/libssh2.a
    )
  add_library(libssh2::lib STATIC IMPORTED)
  add_dependencies(libssh2::lib libssh2)
  sonar_external_project_dirs(libssh2 install_dir)
  set_target_properties(libssh2::lib PROPERTIES
    IMPORTED_LOCATION ${libssh2_install_dir}/${EXTERNAL_INSTALL_LIBDIR}/libssh2.a
    )
  target_include_external_directory(libssh2::lib libssh2 install_dir include)
  set_property(TARGET libssh2::lib PROPERTY
    INTERFACE_LINK_LIBRARIES
      openssl::ssl
      openssl::crypto
      ZLIB::ZLIB
    )
endfunction()

function(build_curl)
  if(TARGET curl)
    sonar_external_project_dirs(curl install_dir)
    return()
  endif()
  find_package(ZLIB REQUIRED)
  build_openssl()
  build_libssh2()
  cmake_parse_arguments(CURL "" "VERSION" "" ${ARGN})
  if(NOT CURL_VERSION)
    set(CURL_VERSION 7.60.0)
  endif()
  message(STATUS "Building curl-${CURL_VERSION}")
  ExternalProject_Add(curl
    URL https://curl.haxx.se/download/curl-${CURL_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    DEPENDS openssl libssh2
    CONFIGURE_COMMAND libsuff=${LIBSUFF} <SOURCE_DIR>/configure
      --disable-ldap
      --disable-ldaps
      --disable-manual
      --disable-shared
      --disable-sspi
      --disable-tls-srp
      --prefix <INSTALL_DIR>
      --without-brotli
      --without-gssapi
      --without-libidn2
      --without-libmetalink
      --without-libpsl
      --without-librtmp
      --with-libssh2=${libssh2_install_dir}
      --without-nghttp2
      --without-nss
      --with-ssl=${openssl_install_dir}
    BUILD_BYPRODUCTS <INSTALL_DIR>/lib/libcurl.a
    )
  add_library(curl::lib STATIC IMPORTED)
  add_dependencies(curl::lib curl)
  sonar_external_project_dirs(curl install_dir)
  set_target_properties(curl::lib PROPERTIES
    IMPORTED_LOCATION ${curl_install_dir}/lib/libcurl.a)
  target_include_external_directory(curl::lib curl install_dir include)
  set_property(TARGET curl::lib PROPERTY
    INTERFACE_LINK_LIBRARIES
      libssh2::lib
      openssl::ssl
      openssl::crypto
      ZLIB::ZLIB
      )
endfunction()

function(build_aws)
  #[====[
  Usage: build_aws(VERSION <version>
                   CURL_VERSION <curl_version>
                   COMPONENTS <component1> <component2>...)

  Will build aws and provide the targets aws::core and aws::<component> for each component listed.

  For example, to build logs and s3:

  build_aws(VERSION 1.3.4 COMPONENTS logs s3)

  After that you can use in your project:
  target_link_libraries(mytarget aws::logs aws::s3)
  #]====]

  cmake_parse_arguments(AWS "" "VERSION" "COMPONENTS" ${ARGN})
  message(STATUS "Building aws-sdk-cpp-${AWS_VERSION} [${AWS_COMPONENTS}]")
  string(REPLACE ";" "$<SEMICOLON>" AWS_BUILD_ONLY "${AWS_COMPONENTS}")
  set(BUILD_BYPRODUCTS "<INSTALL_DIR>/usr/local/${EXTERNAL_INSTALL_LIBDIR}/libaws-cpp-sdk-core.a")
  foreach(component ${AWS_COMPONENTS})
    list(APPEND
      BUILD_BYPRODUCTS
      "<INSTALL_DIR>/usr/local/${EXTERNAL_INSTALL_LIBDIR}/libaws-cpp-sdk-${component}.a")
  endforeach()
  build_openssl()
  build_curl()
  ExternalProject_Add(aws
    URL https://github.com/aws/aws-sdk-cpp/archive/${AWS_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    DEPENDS curl openssl
    CMAKE_COMMAND GIT_CEILING_DIRECTORIES=<INSTALL_DIR> ${CMAKE_COMMAND}
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_MESSAGE=LAZY
      -DBUILD_ONLY=${AWS_BUILD_ONLY}
      -DBUILD_SHARED_LIBS=OFF
      -DENABLE_TESTING=OFF
      -DCMAKE_PREFIX_PATH=${openssl_install_dir}$<SEMICOLON>${curl_install_dir}
    INSTALL_COMMAND DESTDIR=<INSTALL_DIR> ${CMAKE_MAKE_PROGRAM} install
    BUILD_BYPRODUCTS
      "${BUILD_BYPRODUCTS}"
  )
  sonar_external_project_dirs(aws install_dir)
  add_library(aws::core STATIC IMPORTED)
  add_dependencies(aws::core aws)
  find_package(Threads REQUIRED)
  set_target_properties(aws::core PROPERTIES
    IMPORTED_LOCATION ${aws_install_dir}/usr/local/${EXTERNAL_INSTALL_LIBDIR}/libaws-cpp-sdk-core.a)
  set_property(TARGET aws::core PROPERTY
    INTERFACE_LINK_LIBRARIES
      Threads::Threads
      curl::lib
      openssl::ssl
      openssl::crypto
  )
  target_include_external_directory(aws::core aws install_dir usr/local/include)

  foreach(component ${AWS_COMPONENTS})
    set(lib aws::${component})
    add_library(${lib} STATIC IMPORTED)
    add_dependencies(${lib} aws)
    set_target_properties(${lib} PROPERTIES
      IMPORTED_LOCATION
        ${aws_install_dir}/usr/local/${EXTERNAL_INSTALL_LIBDIR}/libaws-cpp-sdk-${component}.a)
    set_property(TARGET ${lib} PROPERTY
      INTERFACE_LINK_LIBRARIES aws::core)
    target_include_external_directory(${lib} aws install_dir usr/local/include)
  endforeach()
endfunction()

function(build_jsoncpp)
  # Usage: build_jsoncpp(VERSION <version>)
  #
  # Generates jsoncpp::lib target to link with
  if(TARGET jsoncpp)
    sonar_external_project_dirs(jsoncpp install_dir)
    return()
  endif()
  cmake_parse_arguments(JSONCPP "" "VERSION;PATCH_FILE" "" ${ARGN})
  if(NOT JSONCPP_VERSION)
    set(JSONCPP_VERSION 1.8.4)
  endif()
  message(STATUS "Building jsoncpp-${JSONCPP_VERSION}")
  set(jsoncpp_lib ${EXTERNAL_INSTALL_LIBDIR}/libjsoncpp.a)
  if(JSONCPP_PATCH_FILE)
    set(patch_command #git checkout . COMMAND
      patch -p1 < ${JSONCPP_PATCH_FILE})
  endif()
  ExternalProject_Add(jsoncpp
    URL https://github.com/open-source-parsers/jsoncpp/archive/${JSONCPP_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    PATCH_COMMAND ${patch_command}
    CMAKE_ARGS
      -DBUILD_SHARED_LIBS=OFF
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_MESSAGE=LAZY
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
    BUILD_BYPRODUCTS
      <INSTALL_DIR>/${jsoncpp_lib}
  )
  ExternalProject_Add_StepTargets(jsoncpp update)
  sonar_external_project_dirs(jsoncpp install_dir)
  add_library(jsoncpp::lib STATIC IMPORTED)
  add_dependencies(jsoncpp::lib jsoncpp)
  set_target_properties(jsoncpp::lib PROPERTIES
    IMPORTED_LOCATION ${jsoncpp_install_dir}/${jsoncpp_lib})
  target_include_external_directory(jsoncpp::lib jsoncpp install_dir include)
endfunction()

function(build_sqlite3)
  cmake_parse_arguments(SQLITE3 "" "URL;SHA1" "" ${ARGN})
  file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/sqlite3.cmake
    "cmake_minimum_required(VERSION 3.8)\n"
    "project(sqlite LANGUAGES C)\n"
    "add_library(sqlite3 sqlite3.c)\n"
    "install(TARGETS sqlite3 DESTINATION lib)\n"
    "install(FILES sqlite3.h DESTINATION include)\n")
  message(STATUS "Building sqlite3 from ${SQLITE3_URL}")
  if (SQLITE3_SHA1)
    set(url_hash SHA1=${SQLITE3_SHA1})
  endif()
  ExternalProject_Add(sqlite3
    URL ${SQLITE3_URL}
    DOWNLOAD_NO_PROGRESS 1
    URL_HASH ${url_hash}
    PATCH_COMMAND
      ${CMAKE_COMMAND} -E
        copy_if_different ${CMAKE_CURRENT_BINARY_DIR}/sqlite3.cmake <SOURCE_DIR>/CMakeLists.txt
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DBUILD_SHARED_LIBS=OFF
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON
      -DCMAKE_INSTALL_MESSAGE=LAZY
    INSTALL_COMMAND DESTDIR=<INSTALL_DIR> ${CMAKE_MAKE_PROGRAM} install
    BUILD_BYPRODUCTS <INSTALL_DIR>/usr/local/lib/libsqlite3.a
    )
  sonar_external_project_dirs(sqlite3 install_dir)
  add_library(sqlite3::lib STATIC IMPORTED)
  add_dependencies(sqlite3::lib sqlite3)
  set_target_properties(sqlite3::lib PROPERTIES
    IMPORTED_LOCATION ${sqlite3_install_dir}/usr/local/lib/libsqlite3.a
    )
  set_property(TARGET sqlite3::lib PROPERTY
    INTERFACE_LINK_LIBRARIES
      ${CMAKE_DL_LIBS}
    )
  target_include_external_directory(sqlite3::lib sqlite3 install_dir usr/local/include)
endfunction()


function(build_mongocxx)
  # builds mongocxx as an external project. Provides mongocxx::lib and
  # bsoncxx::lib
  cmake_parse_arguments(MONGOCXX "" "VERSION;PATCH_FILE;MONGOC_VERSION" "" ${ARGN})
  message(STATUS "Building mongocxx-${MONGOCXX_VERSION}")
  if(MONGOCXX_MONGOC_VERSION)
    build_mongoc(VERSION ${MONGOCXX_MONGOC_VERSION})
  endif()
  if(MONGOCXX_PATCH_FILE)
    set(patch_command git checkout .
      COMMAND patch -p1 < ${MONGOCXX_PATCH_FILE})
  endif()
  sonar_external_project_dirs(mongoc install_dir)
  ExternalProject_Add(mongocxx
    GIT_REPOSITORY https://github.com/mongodb/mongo-cxx-driver.git
    GIT_TAG r${MONGOCXX_VERSION}
    DEPENDS mongoc
    CMAKE_ARGS
      -DBUILD_SHARED_LIBS=OFF
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_MESSAGE=LAZY
      -DCMAKE_PREFIX_PATH=${mongoc_install_dir}
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    INSTALL_COMMAND DESTDIR=<INSTALL_DIR> ${CMAKE_MAKE_PROGRAM} install
    BUILD_BYPRODUCTS
      <INSTALL_DIR>/usr/local/lib/libmongocxx.a
      <INSTALL_DIR>/usr/local/lib/libbsoncxx.a
    PATCH_COMMAND ${patch_command}
  )
  ExternalProject_Add_StepTargets(mongocxx update)
  sonar_external_project_dirs(mongocxx install_dir)

  # generate mongocxx::lib and bsoncxx::lib targets
  foreach(driver mongo bson)
    set(libcxx ${driver}cxx::lib)
    set(libcxx_file usr/local/lib/lib${driver}cxx.a)
    set(libcxx_include usr/local/include/${driver}cxx/v_noabi)

    add_library(${libcxx} STATIC IMPORTED)
    add_dependencies(${libcxx} mongocxx)
    set_target_properties(${libcxx}
      PROPERTIES
        IMPORTED_LOCATION ${mongocxx_install_dir}/${libcxx_file}
        INTERFACE_LINK_LIBRARIES ${driver}::lib
      )
    target_include_external_directory(${libcxx} mongocxx install_dir ${libcxx_include})
  endforeach()
  # bsoncxx require bson lib
  set_property(TARGET bsoncxx::lib
    PROPERTY INTERFACE_LINK_LIBRARIES bson::lib
    APPEND
    )
  # mongocxx requires bsoncxx and mongoc
  set_property(TARGET mongocxx::lib
    PROPERTY INTERFACE_LINK_LIBRARIES bsoncxx::lib mongo::lib
    APPEND
    )
endfunction()

function(build_easylogging)
  # Usage: build_easyloggingpp(VERSION <version> COMPILE_DEFINITIONS <compile definitions>)
  #
  # Generates easyloggingpp::lib target to link with
  cmake_parse_arguments(EASYLOGGING "" "VERSION" "COMPILE_DEFINITIONS" ${ARGN})
  message(STATUS "Building easylogging-${EASYLOGGING_VERSION}")
  ExternalProject_Add(easylogging
    URL https://github.com/muflihun/easyloggingpp/archive/v${EASYLOGGING_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    CMAKE_ARGS
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON
      )
  sonar_external_project_dirs(easylogging install_dir)
  set(easyloggingcc ${easylogging_install_dir}/include/easylogging++.cc)
  set(CMAKE_POSITION_INDEPENDENT_CODE 1)
  add_library(easylogging-lib STATIC ${easyloggingcc})
  add_dependencies(easylogging-lib easylogging)
  set_property(SOURCE ${easyloggingcc} PROPERTY GENERATED 1)
  target_include_directories(easylogging-lib SYSTEM PUBLIC ${easylogging_install_dir}/include)
  target_compile_definitions(easylogging-lib
  PUBLIC
    ELPP_FEATURE_CRASH_LOG
    ELPP_NO_DEFAULT_LOG_FILE
    ELPP_THREAD_SAFE
    ${EASYLOGGING_COMPILE_DEFINITIONS}
  )
endfunction()

function(build_pcre)
  cmake_parse_arguments(PCRE "" "VERSION" "" ${ARGN})
  ExternalProject_Add(pcre
    URL https://ftp.pcre.org/pub/pcre/pcre-${PCRE_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    CONFIGURE_COMMAND <SOURCE_DIR>/configure
      --enable-jit
      --enable-unicode-properties
      --enable-utf
      --prefix <INSTALL_DIR>
    BUILD_BYPRODUCTS <INSTALL_DIR>/lib/libpcre.a
    )
  sonar_external_project_dirs(pcre install_dir)
  add_library(pcre::lib STATIC IMPORTED)
  add_dependencies(pcre::lib pcre)
  set_property(TARGET pcre::lib
    PROPERTY IMPORTED_LOCATION ${pcre_install_dir}/lib/libpcre.a
    )
  target_include_external_directory(pcre::lib pcre install_dir include)
endfunction()

function(use_asio_standalone)
  cmake_parse_arguments(ASIO_STANDALONE "" "DIRECTORY" "COMPILE_DEFINITIONS" ${ARGN})
  add_library(asio::lib INTERFACE IMPORTED)
  set_property(TARGET asio::lib
    PROPERTY
      INTERFACE_INCLUDE_DIRECTORIES ${ASIO_STANDALONE_DIRECTORY}/asio/include)
  set_property(TARGET asio::lib
    PROPERTY
      INTERFACE_COMPILE_DEFINITIONS ${ASIO_STANDALONE_COMPILE_DEFINITIONS})
  find_package(Boost)
  if (Boost_VERSION STRLESS_EQUAL 105300)
    #
    # asio standalone assumes BOOST_NOEXCEPT_OR_NOTHROW is defined, for boost
    # 1.53, this is incorrect
    #
    set_property(TARGET asio::lib
      PROPERTY INTERFACE_COMPILE_DEFINITIONS
      BOOST_NOEXCEPT_OR_NOTHROW=noexcept)
  endif()
endfunction()

function(build_glog)
  if(TARGET glog)
    sonar_external_project_dirs(glog install_dir)
    return()
  endif()
  cmake_parse_arguments(GLOG "" "VERSION" "" ${ARGN})
  if(NOT GLOG_VERSION)
    set(GLOG_VERSION 0.3.5)
  endif()
  message(STATUS "Building glog-${GLOG_VERSION}")
  ExternalProject_Add(glog
    URL https://github.com/google/glog/archive/v${GLOG_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
      -DWITH_GFLAGS=NO
      -DBUILD_SHARED_LIBS=OFF
    BUILD_BYPRODUCTS <INSTALL_DIR>/lib/libglog.a
    )
  sonar_external_project_dirs(glog install_dir)
  add_library(glog::lib STATIC IMPORTED)
  add_dependencies(glog::lib glog)
  set_target_properties(glog::lib PROPERTIES
    IMPORTED_LOCATION ${glog_install_dir}/lib/libglog.a)
  target_include_external_directory(glog::lib glog install_dir include)
endfunction()

function(build_gflags)
  if(TARGET gflags)
    sonar_external_project_dirs(gflags install_dir)
    return()
  endif()
  cmake_parse_arguments(GFLAGS "" "VERSION" "" ${ARGN})
  if(NOT GFLAGS_VERSION)
    set(GFLAGS_VERSION 2.2.1)
  endif()
  message(STATUS "Building gflags-${GFLAGS_VERSION}")
  ExternalProject_Add(gflags
    URL https://github.com/gflags/gflags/archive/v${GFLAGS_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DBUILD_SHARED_LIBS=OFF
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
    BUILD_BYPRODUCTS
      <INSTALL_DIR>/lib/libgflags.a
      )
  sonar_external_project_dirs(gflags install_dir)
  add_library(gflags::lib STATIC IMPORTED GLOBAL)
  add_dependencies(gflags::lib gflags)
  set_target_properties(gflags::lib PROPERTIES
    IMPORTED_LOCATION ${gflags_install_dir}/lib/libgflags.a)
  target_include_external_directory(gflags::lib gflags install_dir include)
endfunction()

function(build_google_api)
  # creates google-api::<component> for each component listed
  cmake_parse_arguments(GOOGLE_API "" "SOURCE_DIR" "COMPONENTS" ${ARGN})
  message(STATUS "Building google-api from ${GOOGLE_API_SOURCE_DIR} [${GOOGLE_API_COMPONENTS}]")
  build_openssl()
  build_libssh2()
  build_curl()
  build_jsoncpp()
  build_glog()
  build_gflags()
  set(google_libs curl_http oauth2 openssl_codec jsoncpp json http utils internal)
  foreach(lib ${google_libs})
    list(APPEND byproducts "<BINARY_DIR>/lib/libgoogleapis_${lib}.a")
  endforeach()
  foreach(component ${GOOGLE_API_COMPONENTS})
    list(APPEND byproducts "<BINARY_DIR>/lib/libgoogle_${component}_api.a")
  endforeach()
  ExternalProject_Add(google_api
    SOURCE_DIR ${GOOGLE_API_SOURCE_DIR}
    DEPENDS curl jsoncpp glog gflags openssl
    CMAKE_ARGS
      -DBUILD_SHARED_LIBS=OFF
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_MESSAGE=LAZY
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON
      -DCMAKE_PREFIX_PATH=${curl_install_dir}$<SEMICOLON>${jsoncpp_install_dir}$<SEMICOLON>${glog_install_dir}$<SEMICOLON>${gflags_install_dir}$<SEMICOLON>${openssl_install_dir}$<SEMICOLON>${libssh2_install_dir}
    BUILD_BYPRODUCTS ${byproducts}
    )
  sonar_external_project_dirs(google_api binary_dir source_dir)
  # google-api-core is the core target that depends on all the core libs
  add_library(google-api-core INTERFACE)
  add_dependencies(google-api-core google_api)
  target_include_external_directory(google-api-core google_api source_dir src)
  foreach(lib curl_http oauth2 openssl_codec jsoncpp json http utils internal)
    target_link_libraries(google-api-core
      INTERFACE
        ${google_api_binary_dir}/lib/libgoogleapis_${lib}.a
      )
  endforeach()
  foreach(component ${GOOGLE_API_COMPONENTS})
    set(library google-api::${component})
    add_library(${library} STATIC IMPORTED)
    add_dependencies(${library} google-api-core)
    set_property(TARGET ${library} PROPERTY
      IMPORTED_LOCATION ${google_api_binary_dir}/lib/libgoogle_${component}_api.a
      )
    target_include_external_directory(${library} google_api source_dir service_apis/${component})
    set_property(TARGET ${library} PROPERTY
      INTERFACE_LINK_LIBRARIES
        google-api-core
        glog::lib
        Threads::Threads
        curl::lib
        jsoncpp::lib
        openssl::ssl
        openssl::crypto
      )
  endforeach()
endfunction()

function(build_s2)
  cmake_parse_arguments(S2 "" "VERSION;PATCH_FILE" "" ${ARGN})
  message(STATUS "Building s2-${S2_VERSION}")
  if(S2_PATCH_FILE)
    set(patch_command patch -p1 < ${S2_PATCH_FILE})
  endif()
  build_openssl()
  ExternalProject_Add(s2
    URL https://github.com/google/s2geometry/archive/${S2_VERSION}.zip
    DOWNLOAD_NO_PROGRESS 1
    DEPENDS openssl
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DBUILD_SHARED_LIBS=OFF
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
      -DCMAKE_PREFIX_PATH=${openssl_install_dir}
    PATCH_COMMAND ${patch_command}
    BUILD_BYPRODUCTS <INSTALL_DIR>/lib/libs2.a
    )
  sonar_external_project_dirs(s2 install_dir)
  add_library(s2::lib STATIC IMPORTED)
  add_dependencies(s2::lib s2)
  set_property(TARGET s2::lib
    PROPERTY IMPORTED_LOCATION ${s2_install_dir}/lib/libs2.a
    )
  set_property(TARGET s2::lib PROPERTY
    INTERFACE_LINK_LIBRARIES
      openssl::crypto
    )
  target_include_external_directory(s2::lib s2 install_dir include)
endfunction()

function(build_bid)
  cmake_parse_arguments(BID "" "PATCH_FILE" "" ${ARGN})
  if(BID_PATCH_FILE)
    set(patch_command patch -p1 < ${BID_PATCH_FILE})
  endif()
  ExternalProject_Add(bid
    URL https://software.intel.com/sites/default/files/m/d/4/1/d/8/IntelRDFPMathLib20U1.tar.gz
    URL_MD5 c9384d2e03a13b35d15e54cf20492cf5
    DOWNLOAD_NO_PROGRESS 1
    CONFIGURE_COMMAND ""
    PATCH_COMMAND ${patch_command}
    BUILD_COMMAND make
      -C <SOURCE_DIR>/LIBRARY
      CC=gcc
      CALL_BY_REF=0
      GLOBAL_RND=1
      GLOBAL_FLAGS=1
      UNCHANGED_BINARY_FLAGS=0
    INSTALL_COMMAND ""
    BUILD_BYPRODUCTS <SOURCE_DIR>/LIBRARY/libbid.a
    )
  add_library(bid::lib STATIC IMPORTED GLOBAL)
  add_dependencies(bid::lib bid)
  sonar_external_project_dirs(bid source_dir)
  set_property(TARGET bid::lib
    PROPERTY IMPORTED_LOCATION ${bid_source_dir}/LIBRARY/libbid.a)
  target_include_external_directory(bid::lib bid source_dir LIBRARY/src)
endfunction()

function(build_jemalloc)
  cmake_parse_arguments(JEMALLOC "" "VERSION" "" ${ARGN})
  message(STATUS "Building jemalloc-${JEMALLOC_VERSION}")
  ExternalProject_Add(jemalloc
    URL https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-${JEMALLOC_VERSION}.tar.bz2
    DOWNLOAD_NO_PROGRESS 1
    CONFIGURE_COMMAND <SOURCE_DIR>/configure
      --prefix <INSTALL_DIR>
      --enable-munmap
    INSTALL_COMMAND make
      install_bin
      install_lib
      install_include
    BUILD_BYPRODUCTS <INSTALL_DIR>/lib/libjemalloc.a
    )
  add_library(jemalloc::lib STATIC IMPORTED GLOBAL)
  add_dependencies(jemalloc::lib jemalloc)
  sonar_external_project_dirs(jemalloc install_dir)
  set_property(TARGET jemalloc::lib
    PROPERTY IMPORTED_LOCATION ${jemalloc_install_dir}/lib/libjemalloc.a)
  target_include_external_directory(jemalloc::lib jemalloc install_dir include)
  find_package(Threads)
  set_property(TARGET jemalloc::lib PROPERTY
    INTERFACE_LINK_LIBRARIES
      Threads::Threads
    )
endfunction()

function(build_stxxl)
  cmake_parse_arguments(STXXL "" "VERSION" "" ${ARGN})
  message(STATUS "Building stxxl-${STXXL_VERSION}")
  ExternalProject_Add(stxxl
    URL https://github.com/stxxl/stxxl/releases/download/${STXXL_VERSION}/stxxl-${STXXL_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    CMAKE_ARGS
      -DBUILD_SHARED_LIBS=OFF
      -DBUILD_STATIC_LIBS=ON
      -DCMAKE_BUILD_TYPE=Release
      -DCMAKE_INSTALL_MESSAGE=LAZY
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
    BUILD_BYPRODUCTS <INSTALL_DIR>/lib/libstxxl.a
    )
  add_library(stxxl::lib STATIC IMPORTED)
  add_dependencies(stxxl::lib stxxl)
  sonar_external_project_dirs(stxxl install_dir)
  set_property(TARGET stxxl::lib
    PROPERTY IMPORTED_LOCATION ${stxxl_install_dir}/lib/libstxxl.a)
  target_include_external_directory(stxxl::lib stxxl install_dir include)
  find_package(OpenMP)
  if(OpenMP_CXX_FOUND)
    set_property(TARGET stxxl::lib PROPERTY
      INTERFACE_LINK_LIBRARIES
        ${OpenMP_CXX_LIBRARIES}
      )
  endif()
endfunction()

function(build_sparsehash)
  cmake_parse_arguments(SPARSEHASH "" "VERSION" "" ${ARGN})
  message(STATUS "Building header-only sparsehash-${SPARSEHASH_VERSION}")
  ExternalProject_Add(sparsehash
    URL https://github.com/sparsehash/sparsehash/archive/sparsehash-${SPARSEHASH_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    PATCH_COMMAND
      sed -i s/google::/GOOGLE_NAMESPACE::/
        src/simple_test.cc
        src/simple_compat_test.cc
    CONFIGURE_COMMAND <SOURCE_DIR>/configure
      --prefix <INSTALL_DIR>
      --enable-namespace=sparsehash
    )
  add_library(sparsehash::header-only INTERFACE IMPORTED)
  add_dependencies(sparsehash::header-only sparsehash)
  sonar_external_project_dirs(sparsehash install_dir)
  target_include_external_directory(sparsehash::header-only sparsehash install_dir include)
endfunction()

function(build_hdfs3)
  cmake_parse_arguments(HDFS3 "" "VERSION;PATCH_FILE" "" ${ARGN})
  message(STATUS "Building hdfs3-${HDFS3_VERSION}")
  if(HDFS3_PATCH_FILE)
    set(patch_command patch -p1 < ${HDFS3_PATCH_FILE})
  endif()
  ExternalProject_Add(hdfs3
    URL https://github.com/jsonar/pivotalrd-libhdfs3/archive/${HDFS3_VERSION}.zip
    DOWNLOAD_NO_PROGRESS 1
    PATCH_COMMAND ${patch_command}
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_MESSAGE=LAZY
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
      -DBUILD_SHARED_LIBS=0
      -DBUILD_STATIC_LIBS=1
    BUILD_BYPRODUCTS <INSTALL_DIR>/lib/libhdfs3.a
    )
  add_library(hdfs3::lib STATIC IMPORTED)
  add_dependencies(hdfs3::lib hdfs3)
  sonar_external_project_dirs(hdfs3 install_dir)
  set_property(TARGET hdfs3::lib
    PROPERTY IMPORTED_LOCATION ${hdfs3_install_dir}/lib/libhdfs3.a)
  target_include_external_directory(hdfs3::lib hdfs3 install_dir include)
  set_property(TARGET hdfs3::lib PROPERTY
    INTERFACE_LINK_LIBRARIES
      krb5
      protobuf
      uuid
    )
endfunction()

function(build_rdkafka)
  cmake_parse_arguments(RDKAFKA "" "VERSION" "" ${ARGN})
  message(STATUS "Building rdkafka-${RDKAFKA_VERSION}")
  build_openssl()
  ExternalProject_Add(rdkafka
    URL https://github.com/edenhill/librdkafka/archive/v${RDKAFKA_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    DEPENDS openssl
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
      -DCMAKE_PREFIX_PATH=${openssl_install_dir}
      -DRDKAFKA_BUILD_EXAMPLES=OFF
      -DRDKAFKA_BUILD_TESTS=OFF
      -DRDKAFKA_BUILD_STATIC=ON
    BUILD_BYPRODUCTS
      <INSTALL_DIR>/${EXTERNAL_INSTALL_LIBDIR}/librdkafka.a
      <INSTALL_DIR>/${EXTERNAL_INSTALL_LIBDIR}/librdkafka++.a
      )
  sonar_external_project_dirs(rdkafka install_dir)
  add_library(rdkafka::c STATIC IMPORTED)
  add_dependencies(rdkafka::c rdkafka)
  set_property(TARGET rdkafka::c
    PROPERTY IMPORTED_LOCATION ${rdkafka_install_dir}/${EXTERNAL_INSTALL_LIBDIR}/librdkafka.a
    )
  target_include_external_directory(rdkafka::c rdkafka install_dir include)

  add_library(rdkafka::cpp STATIC IMPORTED)
  add_dependencies(rdkafka::cpp rdkafka::c)
  set_property(TARGET rdkafka::cpp
    PROPERTY IMPORTED_LOCATION ${rdkafka_install_dir}/${EXTERNAL_INSTALL_LIBDIR}/librdkafka++.a
    )
  set_property(TARGET rdkafka::cpp PROPERTY
    INTERFACE_LINK_LIBRARIES
      rdkafka::c
    )
  # kafka requires sasl2 if it is found in the system
  find_library(sasl2 sasl2)
  if (sasl2)
    set_property(TARGET rdkafka::cpp APPEND PROPERTY
      INTERFACE_LINK_LIBRARIES
      sasl2
      )
  endif()
endfunction()

function(build_geos)
  cmake_parse_arguments(GEOS "" "VERSION" "" ${ARGN})
  message(STATUS "Building geos-${GEOS_VERSION}")
  ExternalProject_Add(geos
    URL https://github.com/OSGeo/geos/archive/${GEOS_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON
      -DGEOS_BUILD_STATIC=1
    BUILD_BYPRODUCTS <INSTALL_DIR>/libgeos.a
    )
  sonar_external_project_dirs(geos install_dir)
endfunction()

function(build_spatialite)
  cmake_parse_arguments(SPATIALITE "" "VERSION" "" ${ARGN})
  message(STATUS "Building spatialite-${SPATIALITE_VERSION}")
  build_geos(VERSION 3.6.2)
  ExternalProject_Add(spatialite
    URL https://www.gaia-gis.it/gaia-sins/libspatialite-${SPATIALITE_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    CONFIGURE_COMMAND <SOURCE_DIR>/configure
      --disable-examples
      --disable-freexl
      --disable-gcp
      --disable-libxml2
      --disable-lwgeom
      --with-geosconfig=${geos_install_dir}/bin/geos-config
      --prefix <INSTALL_DIR>
    BUILD_BYPRODUCTS <INSTALL_DIR>/lib/libspatialite.so
    )
endfunction()

function(build_xerces)
  cmake_parse_arguments(XERCES "" "VERSION;PATCH_FILE" "" ${ARGN})
  if(NOT XERCES_VERSION)
    set(XERCES_VERSION 3.2.1)
  endif()
  if(XERCES_PATCH_FILE)
    set(patch_command patch -p1 < ${XERCES_PATCH_FILE})
  endif()
  message(STATUS "Building xerces-c-${XERCES_VERSION}")
  find_package(ICU COMPONENTS uc)
  ExternalProject_Add(xerces
    URL https://www.apache.org/dist/xerces/c/3/sources/xerces-c-${XERCES_VERSION}.tar.xz
    DOWNLOAD_NO_PROGRESS 1
    PATCH_COMMAND ${patch_command}
    CMAKE_ARGS
      -DBUILD_SHARED_LIBS=OFF
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
      -DCMAKE_INSTALL_MESSAGE=LAZY
      -Dnetwork:BOOL=OFF
      -Dtranscoder=icu
    BUILD_BYPRODUCTS <INSTALL_DIR>/${EXTERNAL_INSTALL_LIBDIR}/libxerces-c-3.2.a
    )
  sonar_external_project_dirs(xerces install_dir)
  add_library(xerces::lib STATIC IMPORTED)
  add_dependencies(xerces::lib xerces)
  set_property(TARGET xerces::lib
    PROPERTY IMPORTED_LOCATION ${xerces_install_dir}/${EXTERNAL_INSTALL_LIBDIR}/libxerces-c-3.2.a
    )
  target_include_external_directory(xerces::lib xerces install_dir include)
  set_property(TARGET xerces::lib APPEND PROPERTY
    INTERFACE_LINK_LIBRARIES
      ICU::uc
    )
endfunction()

function(build_jwt_cpp)
  cmake_parse_arguments(JWT_CPP "" "GIT_HASH" "" ${ARGN})
  if (NOT JWT_CPP_GIT_HASH)
    set(JWT_CPP_GIT_HASH 4f09c53)
  endif()
  message(STATUS "Building jwt-cpp-${JWT_CPP_GIT_HASH}")
  build_openssl()
  ExternalProject_Add(jwt_cpp
    URL https://github.com/pokowaka/jwt-cpp/archive/${JWT_CPP_GIT_HASH}.zip
    DOWNLOAD_NO_PROGRESS 1
    DEPENDS openssl
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DBUILD_SHARED_LIBS=OFF
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
      -DCMAKE_INSTALL_MESSAGE=LAZY
      -DCMAKE_PREFIX_PATH=${openssl_install_dir}
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON
      -DENABLE_TESTS=OFF
    BUILD_BYPRODUCTS <INSTALL_DIR>/lib/libjwt.a
    )
  sonar_external_project_dirs(jwt_cpp install_dir)
  add_library(jwt-cpp::lib STATIC IMPORTED)
  add_dependencies(jwt-cpp::lib jwt_cpp)
  set(libname jwt)
  if(CMAKE_BUILD_TYPE STREQUAL Debug)
    string(APPEND libname d)
  endif()
  set_target_properties(jwt-cpp::lib PROPERTIES
    IMPORTED_LOCATION ${jwt_cpp_install_dir}/lib/lib${libname}.a
    INTERFACE_LINK_LIBRARIES "openssl::ssl;openssl::crypto"
    )
  target_include_external_directory(jwt-cpp::lib jwt_cpp install_dir include)
endfunction()

function(build_tbb)
  cmake_parse_arguments(TBB "" "VERSION" "" ${ARGN})
  if (NOT TBB_VERSION)
    set(TBB_VERSION 2018_U3)
  endif()
  message(STATUS "Building tbb-${TBB_VERSION}")
  ExternalProject_Add(tbb
    URL https://github.com/01org/tbb/archive/${TBB_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND make
      -C <SOURCE_DIR>
      CC=gcc
      CXX=g++
      extra_inc=big_iron.inc
      tbb_build_prefix=out
      tbb
    INSTALL_COMMAND ""
    BUILD_BYPRODUCTS
      <BINARY_DIR>/build/out_release/libtbb.a
      <BINARY_DIR>/build/out_debug/libtbb.a
    )
  sonar_external_project_dirs(tbb source_dir)
  add_library(tbb::lib STATIC IMPORTED)
  add_dependencies(tbb::lib tbb)
  if(CMAKE_BUILD_TYPE STREQUAL Debug)
    set(suffix debug)
  else()
    set(suffix release)
  endif()
  set_target_properties(tbb::lib PROPERTIES
    IMPORTED_LOCATION ${tbb_source_dir}/build/out_${suffix}/libtbb.a
    )
  target_include_external_directory(tbb::lib tbb source_dir include)
endfunction()


function(build_yaml)
  # Usage: build_yaml(VERSION <version>)
  #
  # Generates yaml::lib target to link with
  cmake_parse_arguments(YAML "" "VERSION" "" ${ARGN})
  if(NOT YAML_VERSION)
    set(YAML_VERSION 0.1.7)
  endif()
  message(STATUS "Building yaml-${YAML_VERSION}")
  ExternalProject_Add(yaml
    URL https://github.com/yaml/libyaml/archive/${YAML_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
    INSTALL_COMMAND ""
    BUILD_BYPRODUCTS <BINARY_DIR>/libyaml.a
  )
  add_library(yaml::lib STATIC IMPORTED)
  add_dependencies(yaml::lib yaml)
  sonar_external_project_dirs(yaml binary_dir source_dir)
  set_property(TARGET yaml::lib
    PROPERTY IMPORTED_LOCATION ${yaml_binary_dir}/libyaml.a)
  target_include_external_directory(yaml::lib yaml source_dir include)
endfunction()

