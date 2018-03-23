include(ExternalProject)
include(GNUInstallDirs)
string(REGEX MATCH "^lib(64)?" EXTERNAL_INSTALL_LIBDIR ${CMAKE_INSTALL_LIBDIR})

function(build_mongoc)
  # builds mongoc as an external project. Provides
  # targets mongo::lib and bson::lib
  cmake_parse_arguments(MONGOC "" "VERSION" "" ${ARGN})
  message(STATUS "Building mongo-c-driver-${MONGOC_VERSION}")
  ExternalProject_Add(mongoc
    URL https://github.com/mongodb/mongo-c-driver/releases/download/${MONGOC_VERSION}/mongo-c-driver-${MONGOC_VERSION}.tar.gz
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
      resolv
      z
      snappy
    APPEND
    )
  set_property(TARGET mongo::header-only
    PROPERTY INTERFACE_LINK_LIBRARIES
      bson::header-only
    )
endfunction()

function(build_curl)
  find_package(OpenSSL REQUIRED)
  find_package(ZLIB REQUIRED)
  cmake_parse_arguments(CURL "" "VERSION" "" ${ARGN})
  message(STATUS "Building curl-${CURL_VERSION}")
  ExternalProject_Add(curl
    URL https://curl.haxx.se/download/curl-${CURL_VERSION}.tar.gz
    CONFIGURE_COMMAND <SOURCE_DIR>/configure
      --disable-ldap
      --disable-ldaps
      --disable-manual
      --disable-shared
      --disable-sspi
      --disable-tls-srp
      --prefix <INSTALL_DIR>
      --without-brtoli
      --without-gssapi
      --without-libidn2
      --without-libmetalink
      --without-libpsl
      --without-librtmp
      --without-libssh2
      --without-nghttp2
      --without-nss
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
      OpenSSL::SSL
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

  cmake_parse_arguments(AWS "" "VERSION;CURL_VERSION" "COMPONENTS" ${ARGN})
  message(STATUS "Building aws-sdk-cpp-${AWS_VERSION} [${AWS_COMPONENTS}]")
  string(REPLACE ";" "<SEMICOLON>" AWS_BUILD_ONLY "${AWS_COMPONENTS}")
  set(BUILD_BYPRODUCTS "<INSTALL_DIR>/usr/local/${EXTERNAL_INSTALL_LIBDIR}/libaws-cpp-sdk-core.a")
  foreach(component ${AWS_COMPONENTS})
    list(APPEND
      BUILD_BYPRODUCTS
      "<INSTALL_DIR>/usr/local/${EXTERNAL_INSTALL_LIBDIR}/libaws-cpp-sdk-${component}.a")
  endforeach()
  if(NOT AWS_CURL_VERSION)
    set(AWS_CURL_VERSION 7.59.0)
  endif()
  build_curl(VERSION ${AWS_CURL_VERSION})
  sonar_external_project_dirs(curl install_dir)
  ExternalProject_Add(aws
    GIT_REPOSITORY https://github.com/aws/aws-sdk-cpp.git
    GIT_TAG ${AWS_VERSION}
    DEPENDS curl
    UPDATE_DISCONNECTED 1
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_MESSAGE=LAZY
      -DBUILD_ONLY=${AWS_BUILD_ONLY}
      -DBUILD_SHARED_LIBS=OFF
      -DENABLE_TESTING=OFF
      -DBUILD_OPENSSL=OFF
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
  set(jsoncpp_lib usr/local/${EXTERNAL_INSTALL_LIBDIR}/libjsoncpp.a)
  if(JSONCPP_PATCH_FILE)
    set(patch_command git checkout .
      COMMAND patch -p1 < ${JSONCPP_PATCH_FILE})
  endif()
  ExternalProject_Add(jsoncpp
    GIT_REPOSITORY https://github.com/open-source-parsers/jsoncpp
    GIT_TAG ${JSONCPP_VERSION}
    PATCH_COMMAND ${patch_command}
    UPDATE_DISCONNECTED 1
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_MESSAGE=LAZY
    INSTALL_COMMAND DESTDIR=<INSTALL_DIR> ${CMAKE_MAKE_PROGRAM} install
    BUILD_BYPRODUCTS
      <INSTALL_DIR>/${jsoncpp_lib}
  )
  ExternalProject_Add_StepTargets(jsoncpp update)
  sonar_external_project_dirs(jsoncpp install_dir)
  add_library(jsoncpp::lib STATIC IMPORTED)
  add_dependencies(jsoncpp::lib jsoncpp)
  set_target_properties(jsoncpp::lib PROPERTIES
    IMPORTED_LOCATION ${jsoncpp_install_dir}/${jsoncpp_lib})
  target_include_external_directory(jsoncpp::lib jsoncpp install_dir usr/local/include)
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
    GIT_REPOSITORY https://github.com/muflihun/easyloggingpp.git
    GIT_TAG v${EASYLOGGING_VERSION}
    CONFIGURE_COMMAND ""
    UPDATE_DISCONNECTED 1
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
