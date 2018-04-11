include(ExternalProject)
include(GNUInstallDirs)
string(REGEX MATCH "^lib(64)?" EXTERNAL_INSTALL_LIBDIR ${CMAKE_INSTALL_LIBDIR})

function(sonar_external_project_dirs project)
  # set variables project_<dir> for each of the requested properties
  # Usage:
  #  sonar_external_project_dirs myproject install_dir source_dir...
  #
  #  will create variables myproject_install_dir, myproject_source_dir,...
  #
  string(REPLACE - _ project_var ${project})
  foreach(prop ${ARGN})
    ExternalProject_Get_Property(${project} ${prop})
    set(${project_var}_${prop} ${${prop}} PARENT_SCOPE)
  endforeach()
endfunction()

function(target_include_external_directory target external property dir)
  ExternalProject_Get_Property(${external} ${property})
  set(include_dir ${${property}}/${dir})
  execute_process(COMMAND ${CMAKE_COMMAND} -E make_directory ${include_dir})
  set_property(TARGET ${target}
    PROPERTY INTERFACE_INCLUDE_DIRECTORIES ${include_dir} APPEND)
endfunction()

function(build_openssl)
  cmake_parse_arguments(OPENSSL "" "VERSION" "" ${ARGN})
  message(STATUS "Building openssl-${OPENSSL_VERSION}")
  ExternalProject_Add(openssl
    URL https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ./config
      --prefix=<INSTALL_DIR>
      zlib
      no-shared
    BUILD_BYPRODUCTS
      <INSTALL_DIR>/lib/libssl.a
      <INSTALL_DIR>/lib/libcrypto.a
      )
  sonar_external_project_dirs(openssl install_dir)
  add_library(openssl::ssl STATIC IMPORTED)
  add_dependencies(openssl::ssl openssl)
  set_target_properties(openssl::ssl PROPERTIES
    IMPORTED_LOCATION ${openssl_install_dir}/lib/libssl.a)
  target_include_external_directory(openssl::ssl openssl install_dir include)

  add_library(openssl::crypto STATIC IMPORTED)
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
  ExternalProject_Add(mongoc
    URL https://github.com/mongodb/mongo-c-driver/releases/download/${MONGOC_VERSION}/mongo-c-driver-${MONGOC_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    CONFIGURE_COMMAND <SOURCE_DIR>/configure
      --disable-automatic-init-and-cleanup
      --with-libbson=bundled
      --enable-static
      --disable-shared
      --disable-sasl
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
  find_package(OpenSSL REQUIRED)
  find_package(Threads REQUIRED)
  find_library(rt rt)
  set_property(TARGET mongo::lib
    PROPERTY
    INTERFACE_LINK_LIBRARIES
      OpenSSL::SSL
      ${rt}
      bson::lib
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

function(build_curl)
  find_package(ZLIB REQUIRED)
  # build_openssl()
  # sonar_external_project_dirs(openssl install_dir)
  find_package(OpenSSL REQUIRED)
  cmake_parse_arguments(CURL "" "VERSION" "" ${ARGN})
  message(STATUS "Building curl-${CURL_VERSION}")
  ExternalProject_Add(curl
    URL https://curl.haxx.se/download/curl-${CURL_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    # DEPENDS openssl
    CONFIGURE_COMMAND <SOURCE_DIR>/configure
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
      --without-libssh2
      --without-nghttp2
      --without-nss
      # --with-ssl=${openssl_install_dir}
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
      OpenSSL::SSL # remove if building openssl ourselves
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
  if(NOT TARGET curl)
    build_curl(VERSION 7.59.0)
  endif()
  sonar_external_project_dirs(curl install_dir)
  # sonar_external_project_dirs(openssl install_dir)
  ExternalProject_Add(aws
    URL https://github.com/aws/aws-sdk-cpp/archive/${AWS_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    DEPENDS curl # openssl
    UPDATE_DISCONNECTED 1
    CMAKE_COMMAND GIT_CEILING_DIRECTORIES=<INSTALL_DIR> ${CMAKE_COMMAND}
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_MESSAGE=LAZY
      -DBUILD_ONLY=${AWS_BUILD_ONLY}
      -DBUILD_SHARED_LIBS=OFF
      -DENABLE_TESTING=OFF
      -DBUILD_OPENSSL=OFF
      # -DCMAKE_PREFIX_PATH=${openssl_install_dir}$<SEMICOLON>${curl_install_dir}
      -DCMAKE_PREFIX_PATH=${curl_install_dir}
    INSTALL_COMMAND DESTDIR=<INSTALL_DIR> ${CMAKE_MAKE_PROGRAM} install
    BUILD_BYPRODUCTS
      "${BUILD_BYPRODUCTS}"
  )
  # create aws-update target that can be used when changing versions. run `make
  # aws-update` to update the repo
  ExternalProject_Add_StepTargets(aws update)
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
  cmake_parse_arguments(JSONCPP "" "VERSION;PATCH_FILE" "" ${ARGN})
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
    "add_library(sqlite3 STATIC sqlite3.c)\n"
    "set_property(TARGET sqlite3 PROPERTY POSITION_INDEPENDENT_CODE ON)\n"
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

macro(use_easylogging)
  sonar_external_project_dirs(easylogging source_dir)
  set(easyloggingcc ${easylogging_source_dir}/src/easylogging++.cc)
  set_property(SOURCE ${easyloggingcc} PROPERTY GENERATED 1)
endmacro()

function(build_easylogging)
  # Usage: build_easyloggingpp(VERSION <version> COMPILE_DEFINITIONS <compile definitions>)
  #
  # Generates easyloggingpp::lib target to link with
  cmake_parse_arguments(EASYLOGGING "" "VERSION" "COMPILE_DEFINITIONS" ${ARGN})
  message(STATUS "Building easylogging-${EASYLOGGING_VERSION}")
  ExternalProject_Add(easylogging
    URL https://github.com/muflihun/easyloggingpp/archive/v${EASYLOGGING_VERSION}.tar.gz
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ""
    BUILD_BYPRODUCTS <SOURCE_DIR>/src/easylogging++.cc
    )
  ExternalProject_Add_StepTargets(easylogging update)
  add_library(easylogging::lib INTERFACE IMPORTED)
  add_dependencies(easylogging::lib easylogging)
  use_easylogging()
  set_target_properties(easylogging::lib PROPERTIES INTERFACE_SOURCES ${easyloggingcc})
  target_include_external_directory(easylogging::lib easylogging source_dir src)
  set_property(TARGET easylogging::lib
    PROPERTY
      INTERFACE_COMPILE_DEFINITIONS
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
  cmake_parse_arguments(GLOG "" "VERSION" "" ${ARGN})
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
  cmake_parse_arguments(GFLAGS "" "VERSION" "" ${ARGN})
  message(STATUS "Building gflags-${GFLAGS_VERSION}")
  ExternalProject_Add(gflags
    URL https://github.com/gflags/gflags/archive/v${GFLAGS_VERSION}.tar.gz
    DOWNLOAD_NO_PROGRESS 1
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DBUILD_SHARED_LIBS=OFF
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
    )
endfunction()

function(build_google_api)
  # creates google-api::<component> for each component listed
  cmake_parse_arguments(GOOGLE_API "" "SOURCE_DIR" "COMPONENTS" ${ARGN})
  message(STATUS "Building google-api from ${GOOGLE_API_SOURCE_DIR} [${GOOGLE_API_COMPONENTS}]")
  if(NOT TARGET curl)
    build_curl(VERSION 7.59.0)
  endif()
  sonar_external_project_dirs(curl install_dir)
  if(NOT TARGET jsoncpp)
    build_jsoncpp(VERSION 1.8.4)
  endif()
  sonar_external_project_dirs(jsoncpp install_dir)
  if(NOT TARGET glog)
    build_glog(VERSION 0.3.5)
  endif()
  sonar_external_project_dirs(glog install_dir)
  if(NOT TARGET gflags)
    build_gflags(VERSION 2.2.1)
  endif()
  sonar_external_project_dirs(gflags install_dir)
  set(google_libs curl_http oauth2 openssl_codec jsoncpp json http utils internal)
  foreach(lib ${google_libs})
    list(APPEND byproducts "<BINARY_DIR>/lib/libgoogleapis_${lib}.a")
  endforeach()
  foreach(component ${GOOGLE_API_COMPONENTS})
    list(APPEND byproducts "<BINARY_DIR>/lib/libgoogle_${component}_api.a")
  endforeach()
  ExternalProject_Add(google_api
    SOURCE_DIR ${GOOGLE_API_SOURCE_DIR}
    DEPENDS curl jsoncpp glog gflags
    CMAKE_ARGS
      -DBUILD_SHARED_LIBS=OFF
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_MESSAGE=LAZY
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON
      -DCMAKE_PREFIX_PATH=${curl_install_dir}$<SEMICOLON>${jsoncpp_install_dir}$<SEMICOLON>${glog_install_dir}$<SEMICOLON>${gflags_install_dir}
    BUILD_BYPRODUCTS ${byproducts}
    )
  sonar_external_project_dirs(google_api binary_dir source_dir)
  # google-api::lib is the core target that depends on all the core libs
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
      )
  endforeach()
endfunction()

function(build_s2)
  cmake_parse_arguments(S2 "" "VERSION;PATCH_FILE" "" ${ARGN})
  message(STATUS "Building s2-${S2_VERSION}")
  if(S2_PATCH_FILE)
    set(patch_command patch -p1 < ${S2_PATCH_FILE})
  endif()
  if(NOT TARGET openssl)
    build_openssl(VERSION 1.0.2o)
  endif()
  sonar_external_project_dirs(openssl install_dir)
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
  ExternalProject_Add(bid
    URL https://software.intel.com/sites/default/files/m/d/4/1/d/8/IntelRDFPMathLib20U1.tar.gz
    URL_MD5 c9384d2e03a13b35d15e54cf20492cf5
    DOWNLOAD_NO_PROGRESS ON
    CONFIGURE_COMMAND ""
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
    INSTALL_COMMAND ${CMAKE_MAKE_PROGRAM}
      install_bin
      install_lib
      install_include
    BUILD_BYPRODUCTS <INSTALL_DIR>/lib/libjemalloc.a
    )
  add_library(jemalloc::lib STATIC IMPORTED)
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
