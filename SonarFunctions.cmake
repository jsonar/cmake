include(GetGitRevisionDescription)
function(sonar_cpack_version _major _minor _patch)
  git_describe(version --match "v*")
  set(regex "v([0-9]+)\.([0-9]+)\.([0-9]+)(.*)")
  if (NOT ${version} MATCHES ${regex})
    message(FATAL_ERROR "git tag '${version}' format does not match vMAJOR.MINOR.PATCH[EXTRA]")
  endif()
  if (CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(version "${version}-dbg")
  endif()
  string(REGEX REPLACE "${regex}" "\\1" major "${version}")
  string(REGEX REPLACE "${regex}" "\\2" minor "${version}")
  string(REGEX REPLACE "${regex}" "\\3" patch "${version}")
  if (NOT SHORT_VERSION)
    string(REGEX REPLACE "${regex}" "\\4" extra "${version}")
  endif()
  message(STATUS "Detected ${PROJECT_NAME} version: ${major}.${minor}.${patch}${extra}")
  set(${_major} "${major}" PARENT_SCOPE)
  set(${_minor} "${minor}" PARENT_SCOPE)
  set(${_patch} "${patch}${extra}" PARENT_SCOPE)
endfunction()

function(sonar_git_info _describe _hash)
  get_git_head_revision(refspec hash)
  set(${_hash} ${hash} PARENT_SCOPE)
  git_describe(version --match "v*")
  set(${_describe} ${version} PARENT_SCOPE)
endfunction()

function(sonar_set_version version)
  sonar_cpack_version(major minor patch)
  set(${version} "${major}.${minor}.${patch}" PARENT_SCOPE)
endfunction()

function(sonar_detect_distribution _os)
  if (CMAKE_SYSTEM_NAME STREQUAL "Linux")
    if (EXISTS "/etc/os-release")
      file(STRINGS "/etc/os-release" os_release)
      foreach(kv ${os_release})
        if (kv MATCHES "^ID=\"?([^\"]+)\"?$")
          set(os_id ${CMAKE_MATCH_1})
        endif()
        if (kv MATCHES "^ID_LIKE=\"?([^\"]+)\"?$")
          set(os_id_like ${CMAKE_MATCH_1})
        endif()
      endforeach()
    elseif(EXISTS "/etc/redhat-release")
      set(os_id "rhel")
    endif()
    set(os "${os_id} ${os_id_like}")
  else()
    set(os ${CMAKE_SYSTEM_NAME})
  endif()
  message(STATUS "Detected distribution: ${os}")
  set(${_os} "${os}" PARENT_SCOPE)
endfunction()

function(sonar_cpack_generator _cpack)
  sonar_detect_distribution(os)
  if (os MATCHES "rhel")
    set(cpack_generator "RPM")
  elseif (os MATCHES "debian")
    set(cpack_generator "DEB")
  elseif (os MATCHES "arch")
    set(cpack_generator "TGZ")
  else()
    message(STATUS "Unknown distribution ${os} - will create a tarball")
    set(cpack_generator "TGZ")
  endif()
  set(${_cpack} "${cpack_generator}" PARENT_SCOPE)
endfunction()

function(sonar_cpack_filename _filename)
  if (NOT DEFINED CPACK_GENERATOR)
    sonar_cpack_generator(CPACK_GENERATOR)
  endif()
  if (${CPACK_GENERATOR} STREQUALS "RPM")
    execute_process(COMMAND uname "-m"
      OUTPUT_VARIABLE CPACK_RPM_PACKAGE_ARCHITECTURE
      OUTPUT_STRIP_TRAILING_WHITESPACE)
    execute_process(
      COMMAND rpm "-q" "--queryformat" "%{RELEASE}" rpm
      COMMAND rev
      COMMAND cut "-d." "-f1"
      COMMAND rev
      OUTPUT_VARIABLE RHEL
      OUTPUT_STRIP_TRAILING_WHITESPACE)
    set (CPACK_PACKAGE_FILE_NAME
      "${CPACK_PACKAGE_NAME}-${CPACK_PACKAGE_VERSION_MAJOR}.${CPACK_PACKAGE_VERSION_MINOR}.${CPACK_PACKAGE_VERSION_PATCH}${CPACK_PACKAGE_VERSION_EXTRA}.${RHEL}.${CPACK_PACKAGE_VENDOR}.${CPACK_RPM_PACKAGE_ARCHITECTURE}" PARENT_SCOPE)
    set(CPACK_RPM_EXCLUDE_FROM_AUTO_FILELIST_ADDITION "${CPACK_PACKAGING_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}/pkgconfig" PARENT_SCOPE)
  endif()
endfunction()

function(sonar_find_libraries)
  foreach(lib ${ARGV})
    find_library(lib${lib} ${lib} PATHS /usr/lib64/mysql /usr/local PATH_SUFFIXES lib mysql/lib)
    set(lib${lib} ${lib${lib}} PARENT_SCOPE)
    if ((DEFINED lib${lib}) AND (${lib${lib}} MATCHES "NOTFOUND"))
      set(DEPS_ERROR TRUE)
      set(FAILED_DEPS "${FAILED_DEPS} lib${lib}")
    elseif(DEBUG_OUTPUT)
      message(STATUS "Library was found at: ${lib${lib}}")
    endif()
  endforeach()

  if(DEPS_ERROR)
    set(DEPS_OK FALSE CACHE BOOL "If all the dependencies were found.")
    message(FATAL_ERROR "Cannot find dependencies: ${FAILED_DEPS}")
  endif()
endfunction()

function(sonar_external_project_dirs project)
  # set variables project_<dir> for each of the requested properties
  # Usage:
  #  sonar_external_project_dirs myproject install_dir source_dir...
  #
  #  will create variables myproject_install_dir, myproject_source_dir,...
  #
  foreach(prop ${ARGN})
    ExternalProject_Get_Property(${project} ${prop})
    set(${project}_${prop} ${${prop}} PARENT_SCOPE)
  endforeach()
endfunction()

function(sonar_deps _out deps)
  foreach(dep ${ARGN})
    list(APPEND deps ${dep})
  endforeach()
  string(REPLACE ";" ", " _deps "${deps}")
  set(${_out} ${_deps} PARENT_SCOPE)
endfunction()

function(target_include_external_directory target external property dir)
  ExternalProject_Get_Property(${external} ${property})
  set(include_dir ${${property}}/${dir})
  execute_process(COMMAND ${CMAKE_COMMAND} -E make_directory ${include_dir})
  set_property(TARGET ${target}
    PROPERTY INTERFACE_INCLUDE_DIRECTORIES ${include_dir} APPEND)
endfunction()


function(build_mongoc_git tag)
  # builds mongoc as an external directory. Provides
  # targets mongo::lib and bson::lib
  include(ExternalProject)
  ExternalProject_Add(mongoc
    GIT_REPOSITORY https://github.com/mongodb/mongo-c-driver.git
    GIT_TAG ${tag}
    #UPDATE_DISCONNECTED 1 # uncomment for cmake 3.8
    UPDATE_COMMAND ""
    CONFIGURE_COMMAND <SOURCE_DIR>/autogen.sh
      --with-libbson=bundled
      --enable-static
      --disable-sasl
      --disable-tests
      --prefix=<INSTALL_DIR>
    BUILD_BYPRODUCTS <INSTALL_DIR>/lib/libmongoc-1.0.a <INSTALL_DIR>/lib/libbson-1.0.a
    )
  ExternalProject_Get_Property(mongoc install_dir)
  foreach(driver mongo bson)
    set(lib ${driver}::lib)
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
      IMPORTED_LOCATION ${install_dir}/${archive})
    target_include_external_directory(${lib} mongoc install_dir ${include})
  endforeach()
  # mongoc requires openssl, rt and bson::lib
  find_package(OpenSSL REQUIRED)
  find_library(rt rt)
  set_property(TARGET mongo::lib
    PROPERTY
    INTERFACE_LINK_LIBRARIES OpenSSL::SSL ${rt} bson::lib
    APPEND
  )
endfunction()

function(sonar_python3_package_dir _out)
  sonar_detect_distribution(os)
  if (os MATCHES "debian")
    set(python_path lib/python3/dist-packages)
  else()
    set(python_path lib/python3.4/site-packages)
  endif()
  set(${_out} ${python_path} PARENT_SCOPE)
endfunction()

function(sonar_vendor)
  cmake_parse_arguments(VENDOR "" "OUTPUT_VARIABLE" "" ${ARGN})
  set(${VENDOR_OUTPUT_VARIABLE} jsonar PARENT_SCOPE)
endfunction()

function(set_package_file_name_for_component)
  # set_package_file_name_for_component(FILE_NAME autoparts COMPONENT autoparts)
  cmake_parse_arguments(PKG "" "FILE_NAME;COMPONENT" "" ${ARGN})
  sonar_cpack_generator(generator)
  if(NOT DEFINED CPACK_PACKAGE_VERSION_MAJOR)
    sonar_cpack_version(CPACK_PACKAGE_VERSION_MAJOR
      CPACK_PACKAGE_VERSION_MINOR
      CPACK_PACKAGE_VERSION_PATCH)
  endif()
  if(generator STREQUAL "RPM")
    execute_process(COMMAND uname "-m"
      OUTPUT_VARIABLE CPACK_RPM_PACKAGE_ARCHITECTURE
      OUTPUT_STRIP_TRAILING_WHITESPACE)
    execute_process(
      COMMAND rpm "-q" "--queryformat" "%{RELEASE}" rpm
      COMMAND rev
      COMMAND cut "-d." "-f1"
      COMMAND rev
      OUTPUT_VARIABLE RHEL
      OUTPUT_STRIP_TRAILING_WHITESPACE)
    sonar_vendor(OUTPUT_VARIABLE vendor)
    set (package_file_name
      "${PKG_FILE_NAME}-${CPACK_PACKAGE_VERSION_MAJOR}.${CPACK_PACKAGE_VERSION_MINOR}.${CPACK_PACKAGE_VERSION_PATCH}${CPACK_PACKAGE_VERSION_EXTRA}.${RHEL}.${vendor}.${CPACK_RPM_PACKAGE_ARCHITECTURE}")
  elseif(generator STREQUAL "DEB")

    execute_process(COMMAND dpkg "--print-architecture"
      OUTPUT_VARIABLE CPACK_DEBIAN_PACKAGE_ARCHITECTURE
      OUTPUT_STRIP_TRAILING_WHITESPACE)
    string(REPLACE "-" "~" DEBIAN_VERSION_NUMBER
      "${CPACK_PACKAGE_VERSION_MAJOR}.${CPACK_PACKAGE_VERSION_MINOR}.${CPACK_PACKAGE_VERSION_PATCH}${CPACK_PACKAGE_VERSION_EXTRA}")
    if (NOT DEFINED DEBIAN_REVISION)
      set(DEBIAN_REVISION 1)
    endif()
    execute_process(COMMAND lsb_release "-ir"
      COMMAND cut "-f2"
      COMMAND xargs
      COMMAND tr "[ [:upper:]]" "[+[:lower:]]"
      OUTPUT_VARIABLE DEBIAN_OS
      OUTPUT_STRIP_TRAILING_WHITESPACE)
    set(DEBIAN_REVISION_NUMBER "${DEBIAN_REVISION}${DEBIAN_OS}")
    set(package_file_name
      "${PKG_FILE_NAME}_${DEBIAN_VERSION_NUMBER}-${DEBIAN_REVISION_NUMBER}_${CPACK_DEBIAN_PACKAGE_ARCHITECTURE}")
  elseif(generator STREQUAL "TGZ")
    set (package_file_name
      "${PKG_FILE_NAME}-${CPACK_PACKAGE_VERSION_MAJOR}.${CPACK_PACKAGE_VERSION_MINOR}.${CPACK_PACKAGE_VERSION_PATCH}${CPACK_PACKAGE_VERSION_EXTRA}-Linux")
  endif()

  set(CPACK_${PKG_COMPONENT}_FILE_NAME ${package_file_name} PARENT_SCOPE)
endfunction()

