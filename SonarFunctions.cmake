include(GetGitRevisionDescription)

function(sonar_cpack_version major_var minor_var patch_var)
  git_describe(version --match "v*")
  set(regex "v([0-9]+)\\.([0-9]+)\\.([0-9]+(\\.[0-9]+)*)(.*)")
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
    string(REGEX REPLACE "${regex}" "\\5" extra "${version}")
  endif()
  message(STATUS "Detected ${PROJECT_NAME} version: ${major}.${minor}.${patch}${extra}")
  set(${major_var} "${major}" PARENT_SCOPE)
  set(${minor_var} "${minor}" PARENT_SCOPE)
  set(${patch_var} "${patch}${extra}" PARENT_SCOPE)
endfunction()

function(sonar_git_info describe_var hash_var)
  get_git_head_revision(refspec hash)
  set(${hash_var} ${hash} PARENT_SCOPE)
  git_describe(version --match "v*")
  set(${describe_var} ${version} PARENT_SCOPE)
endfunction()

function(sonar_set_version version_var)
  sonar_cpack_version(major minor patch)
  set(${version_var} "${major}.${minor}.${patch}" PARENT_SCOPE)
endfunction()

function(sonar_cpack_generator cpack_generator_var)
  if(NOT SONAR_CPACK_GENERATOR)
    set(SONAR_CPACK_GENERATOR TGZ CACHE STRING "sonar cpack generator")
  endif()
  set(${cpack_generator_var} "${SONAR_CPACK_GENERATOR}" PARENT_SCOPE)
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

function(sonar_deps deps_var deps)
  foreach(dep ${ARGN})
    list(APPEND deps ${dep})
  endforeach()
  foreach(dep ${${_out}})
    list(APPEND deps ${dep})
  endforeach()
  string(REPLACE ";" ", " _deps "${deps}")
  set(${deps_var} ${_deps} PARENT_SCOPE)
endfunction()

function(sonar_python_version python_version_var)
  cmake_parse_arguments(PARSE_ARGV 1 PYTHON "" "SETUPTOOLS_VERSION" "")
  sonar_set_version(version)
  set(devel_regex "([0-9]+\\.[0-9]+(\\.[0-9]+)*)-devel(op)?(-.*)?")
  set(regex "([0-9]+\\.[0-9]+(\\.[0-9]+)*)(-.*)?")
  if(version MATCHES ${devel_regex})
    # we have a long version, that is incompatible with python versioning
    string(REGEX REPLACE "${devel_regex}" "\\1.dev0" python_version ${version})
  elseif(version MATCHES ${regex})
    string(REGEX REPLACE "${regex}" "\\1" python_version ${version})
  else()
    set(python_version ${version})
  endif()
  set(${python_version_var} ${python_version} PARENT_SCOPE)
endfunction()

macro(add_python_target)
  cmake_parse_arguments(PYTHON_PACKAGE
    "BUILD_WHEEL;BUILD_IN_SOURCE;NO_PARENT_SCOPE"
    "NAME;DESTINATION"
    ""
    ${ARGN})
  sonar_python_version(PYTHON_PACKAGE_VERSION)
  if(NOT PYTHON_EXECUTABLE)
    find_package(PythonInterp 3 REQUIRED)
  endif()
  if (PYTHON_PACKAGE_BUILD_IN_SOURCE)
    set(working_directory ${CMAKE_CURRENT_SOURCE_DIR})
  else()
    if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/setup.py.in)
      set(working_directory ${CMAKE_CURRENT_BINARY_DIR})
    else()
      set(working_directory ${CMAKE_CURRENT_SOURCE_DIR})
    endif()
  endif()
  if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/setup.py.in)
    configure_file(setup.py.in ${working_directory}/setup.py)
  endif()
  if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/version.py.in)
    message(FATAL_ERROR "add_python_target ignores version.py.in. Please remove your existing version")
  endif()
  file(WRITE ${CMAKE_CURRENT_SOURCE_DIR}/version.py
    "__version__ = '${PYTHON_PACKAGE_VERSION}'\n"
    "__describe__ = '${GIT_DESCRIBE}'\n"
    "__revision__ = '${GIT_HASH}'\n"
    "__build_type__ = '${CMAKE_BUILD_TYPE}'\n"
    )
  if(PYTHON_PACKAGE_BUILD_WHEEL)
    execute_process(COMMAND ${PYTHON_EXECUTABLE} -m wheel version
      RESULT_VARIABLE NOT_HAS_WHEEL)
    if(NOT_HAS_WHEEL)
      message(FATAL_ERROR "Cannot find python wheel. Please install it manually. Try: ${PYTHON_EXECUTABLE} -m pip install wheel")
    endif()
    message(STATUS "Building python wheel for ${PYTHON_PACKAGE_NAME}-${PYTHON_PACKAGE_VERSION}")
    string(REPLACE "-" "_" PYTHON_WHEEL_FILENAME ${PYTHON_PACKAGE_NAME})
    string(APPEND
      PYTHON_WHEEL_FILENAME
        "-"
        ${PYTHON_PACKAGE_VERSION}
        "-py3-none-any.whl"
      )
    set(wheel ${working_directory}/dist/${PYTHON_WHEEL_FILENAME})
    add_custom_command(OUTPUT ${wheel}
      COMMAND ${PYTHON_EXECUTABLE} setup.py bdist_wheel
      WORKING_DIRECTORY ${working_directory}
      )
    add_custom_target(${PYTHON_PACKAGE_NAME} ALL
      DEPENDS ${wheel}
      )
    if(NOT PYTHON_PACKAGE_DESTINATION)
      set(PYTHON_PACKAGE_DESTINATION lib/sonar/wheels)
    endif()
    message(STATUS "Installing ${PYTHON_PACKAGE_NAME}-${PYTHON_PACKAGE_VERSION}.whl to ${PYTHON_PACKAGE_DESTINATION}")
    install(FILES ${wheel} DESTINATION ${PYTHON_PACKAGE_DESTINATION})
    get_filename_component(destination_parent ${PYTHON_PACKAGE_DESTINATION} DIRECTORY)
    set(filelist ${CPACK_RPM_EXCLUDE_FROM_AUTO_FILELIST_ADDITION})
    list(APPEND filelist
      ${CMAKE_INSTALL_PREFIX}/${PYTHON_PACKAGE_DESTINATION}
      ${CMAKE_INSTALL_PREFIX}/${destination_parent})
    if (PYTHON_PACKAGE_NO_PARENT_SCOPE)
      set(CPACK_RPM_EXCLUDE_FROM_AUTO_FILELIST_ADDITION ${filelist})
    else()
      set(CPACK_RPM_EXCLUDE_FROM_AUTO_FILELIST_ADDITION ${filelist} PARENT_SCOPE)
    endif()
  else()
    # installing directly onto the system
    if(PYTHON_PACKAGE_DESTINATION)
      message(FATAL_ERROR "DESTINATION is ignored without BUILD_WHEEL")
    endif()
    set(timestamp ${PYTHON_PACKAGE_NAME}-timestamp)
    add_custom_command(OUTPUT ${timestamp}
      COMMAND ${PYTHON_EXECUTABLE} setup.py ${cmd}
      COMMAND ${CMAKE_COMMAND} -E touch ${CMAKE_CURRENT_BINARY_DIR}/${timestamp}
      WORKING_DIRECTORY ${working_directory}
      )
    # there is no one file generated, so we use a timestamp
    add_custom_target(${PYTHON_PACKAGE_NAME} ALL
      DEPENDS ${timestamp}
      )
    install(CODE "
      execute_process(
        COMMAND ${PYTHON_EXECUTABLE}
          setup.py install
            --force
            --root=\$ENV{DESTDIR}
            --prefix=${CMAKE_INSTALL_PREFIX}
        WORKING_DIRECTORY ${working_directory}
        )"
      )
  endif()
endmacro()

function(create_venv)
  # (optionally) delete virtual environment if one exists and create new one.
  cmake_parse_arguments(VENV "KEEP_EXISTING_VENV;ONLY_USE_REQUIREMENTS" "PYTHON_VERSION" "" ${ARGN})
  if(VENV_KEEP_EXISTING_VENV)
    set(DELETE_VENV_COMMAND "")
  else()
    set(DELETE_VENV_COMMAND "rm -rf \${VENV};")
  endif()
  if(VENV_ONLY_USE_REQUIREMENTS)
    set(INSTALL_COMMAND "\n\${VPIP} install \${PIP_FLAGS} -r\${REQUIREMENTS_PATH}")
  else()
    set(INSTALL_COMMAND "\n\${VPIP} install \${PIP_FLAGS} --upgrade \${SONAR_PACKAGE_NAME}")
  endif()
  set(POPULATE_PIP_COMMANDS "VPIP=\${VENV}/bin/pip"
    "\nPIP_FLAGS=\"--no-index --find-links /usr/lib/sonar/wheels --quiet\"")
  set(PYTHON_VENV_COMMANDS
    "${DELETE_VENV_COMMAND}\n${POPULATE_PIP_COMMANDS}"
    "\npython${VENV_PYTHON_VERSION} -m venv \${VENV}"
    "\n\${VPIP} install \${PIP_FLAGS} --upgrade pip;${INSTALL_COMMAND}"
    PARENT_SCOPE)
endfunction()

function(configure_post_install)
  cmake_parse_arguments(POST "KEEP_EXISTING_VENV;ONLY_USE_REQUIREMENTS" "TARGET;TARGET_OUTPUT;PYTHON_VERSION;UNINSTALL_TARGET;UNINSTALL_TARGET_OUTPUT" "" ${ARGN})
  if(NOT POST_TARGET_OUTPUT)
    set(POST_TARGET_OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/post)
  endif()
  if(POST_UNINSTALL_TARGET)
    configure_post_uninstall(TARGET ${POST_UNINSTALL_TARGET} TARGET_OUTPUT ${POST_UNINSTALL_TARGET_OUTPUT})
    set(CPACK_RPM_POST_UNINSTALL_SCRIPT_FILE ${CPACK_RPM_POST_UNINSTALL_SCRIPT_FILE} PARENT_SCOPE)
  endif()
  set(CPACK_RPM_POST_INSTALL_SCRIPT_FILE ${POST_TARGET_OUTPUT} PARENT_SCOPE)
  if (EXISTS "${POST_TARGET}")
    if(POST_KEEP_EXISTING_VENV)
      set(KEEP_EXISTING_VENV_VARIABLE "DONT_DELETE_EXISTING")
    endif()
    if(POST_ONLY_USE_REQUIREMENTS)
      set(ONLY_USE_REQUIREMENTS_VARIABLE "ONLY_USE_REQUIREMENTS")
    endif()
    create_venv(PYTHON_VERSION ${POST_PYTHON_VERSION} ${ONLY_USE_REQUIREMENTS_VARIABLE} ${KEEP_EXISTING_VENV_VARIABLE})
    configure_file(${POST_TARGET} ${POST_TARGET_OUTPUT} @ONLY)
  else()
    message(WARNING "configure_post_install could not find POST_TARGET file ${POST_TARGET}")
  endif()
endfunction()

function(configure_post_uninstall)
  cmake_parse_arguments(POSTUN "" "TARGET;TARGET_OUTPUT" "" ${ARGN})
  message("running configure_post_uninstall on ${POSTUN_TARGET}")
  if(NOT POSTUN_TARGET_OUTPUT)
    set(POSTUN_TARGET_OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/postun)
  endif()
  set(CPACK_RPM_POST_UNINSTALL_SCRIPT_FILE ${POSTUN_TARGET_OUTPUT} PARENT_SCOPE)
  set(PYTHON_REMOVE_VENV_COMMAND "rm -r \${VENV}")
  configure_file(${POSTUN_TARGET} ${POSTUN_TARGET_OUTPUT} @ONLY)
endfunction()

function(sonar_vendor)
  cmake_parse_arguments(VENDOR "" "OUTPUT_VARIABLE" "" ${ARGN})
  set(${VENDOR_OUTPUT_VARIABLE} jsonar PARENT_SCOPE)
endfunction()

function(set_package_and_file_name_for_component)
  # set_package_and_file_name_for_component(FILE_NAME autoparts COMPONENT autoparts)
  cmake_parse_arguments(PKG "" "FILE_NAME;COMPONENT" "" ${ARGN})
  sonar_cpack_generator(generator)
  set(local_gen ${generator})
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
    set(local_gen "DEBIAN")
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
      "${PKG_FILE_NAME}-${CPACK_PACKAGE_VERSION_MAJOR}.${CPACK_PACKAGE_VERSION_MINOR}.${CPACK_PACKAGE_VERSION_PATCH}${CPACK_PACKAGE_VERSION_EXTRA}")
  endif()

  if(NOT DEFINED CPACK_PACKAGE_FILE_NAME)
    set(CPACK_PACKAGE_FILE_NAME ${package_file_name} PARENT_SCOPE)
  endif()
  set(CPACK_${PKG_COMPONENT}_FILE_NAME ${package_file_name} PARENT_SCOPE)
  set(CPACK_${generator}_${PKG_COMPONENT}_PACKAGE_NAME ${PKG_COMPONENT} PARENT_SCOPE)
  set(CPACK_${local_gen}_${PKG_COMPONENT}_PACKAGE_NAME ${PKG_COMPONENT} PARENT_SCOPE)
endfunction()

macro(add_java_dependency)
  cmake_parse_arguments(JAVA "" "VERSION" "" ${ARGN})

  if (NOT JAVA_VERSION)
    set(JAVA_VERSION "1:1.8.0.232")
  endif()

  sonar_deps(CPACK_RPM_PACKAGE_REQUIRES
    "java-1.8.0-openjdk >= ${JAVA_VERSION}"
    )

endmacro()

include(CheckCXXCompilerFlag)
function(add_supported_compiler_options)
  cmake_parse_arguments(COMPILER_OPTION "VERBOSE;REQUIRED" "TARGET;SCOPE" "OPTIONS" ${ARGN})
  if(COMPILER_OPTION_VERBOSE)
    set(quiet FALSE)
  else()
    set(quiet TRUE)
  endif()
  foreach(option ${COMPILER_OPTION_OPTIONS})
    # compilers don't always warn for unsupported negative options. Make it positive instead
    string(REGEX REPLACE "^(-.)no-(.+$)" "\\1\\2" pos_option ${option})
    set(CMAKE_REQUIRED_LIBRARIES ${pos_option}) # -fsanizite=X is needed in linkage as well
    set(CMAKE_REQUIRED_QUIET ${quiet})
    string(REPLACE - _ option_name ${option})
    check_cxx_compiler_flag("${pos_option}" has_flag_${option_name})
    if(has_flag_${option_name})
      message(STATUS "Adding compiler option ${option}")
      target_compile_options(${COMPILER_OPTION_TARGET} ${COMPILER_OPTION_SCOPE} ${option})
    else()
      set(message "Skipping compiler option ${option} (not supported)")
      if(COMPILER_OPTION_REQUIRED)
        message(FATAL_ERROR ${message})
      else()
        message(STATUS ${message})
      endif()
    endif()
  endforeach()
endfunction()

function(build_docs product)
  # Usage: build-docs(<name> PRODUCT <product> VENDOR <vendor> INDEX <list of sections>)
  cmake_parse_arguments(PARSE_ARGV 1 DOCS "" "PRODUCT;VENDOR;TARGET" "INDEX")
  if(NOT DOCS_INDEX)
    message(FATAL_ERROR "Cannot build documentation for ${product} with empty index")
  endif()

  find_package(Sphinx)
  if(SPHINX_EXECUTABLE)
    message(STATUS "Building docs for ${product}: ${DOCS_VENDOR} ${DOCS_PRODUCT}")
  else()
    message(WARNING "Sphinx executable not found - not building docs for ${product}")
    return()
  endif()

  sonar_cpack_version(DOCS_VERSION_MAJOR DOCS_VERSION_MINOR DOCS_VERSION_PATCH)
  if(NOT DEFINED SPHINX_THEME)
    set(SPHINX_THEME nature)
  endif()

  execute_process(COMMAND date +%Y
    OUTPUT_VARIABLE year
    OUTPUT_STRIP_TRAILING_WHITESPACE)

  if(NOT DOCS_TARGET)
    set(DOCS_TARGET docs)
  endif()
  add_custom_target(docs-${product})
  add_dependencies(${DOCS_TARGET} docs-${product})
  set(index ${product}-index)
  set(title "${DOCS_VENDOR} ${DOCS_PRODUCT}")
  set(Product ${DOCS_PRODUCT})
  string(REPLACE ";" "\n   " toc "${DOCS_INDEX}")
  configure_file(index.rst.in ${CMAKE_CURRENT_SOURCE_DIR}/${product}-index.rst)
  configure_file(conf.py.in ${product}/conf.py)
  foreach(format html pdf)
    add_custom_target(docs-${product}-${format}
      COMMAND ${SPHINX_EXECUTABLE}
        -q
        -b ${format}
        -c ${CMAKE_CURRENT_BINARY_DIR}/${product}
        -E
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_BINARY_DIR}/${product}/${format}
      COMMENT "Building docs-${product} ${format} documentation with Sphinx")
    add_dependencies(docs-${product} docs-${product}-${format})
  endforeach()
endfunction()

function(sonar_install)
  set(targets ${ARGV})
  set_property(TARGET ${targets}
    PROPERTY INSTALL_RPATH \$ORIGIN/../lib)
  install(TARGETS ${targets}
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    )
  foreach(target ${targets})
    get_target_property(type ${target} TYPE)
    if (type STREQUAL "EXECUTABLE")
      list(APPEND exes $<TARGET_FILE:${target}>)
    elseif(type STREQUAL "SHARED_LIBRARY")
      list(APPEND libs $<TARGET_FILE:${target}>)
    endif()
    if(exes)
      set(executables "EXECUTABLES ${exes}")
    endif()
    if(libs)
      set(libraries "LIBRARIES ${libs}")
    endif()
    if(exes OR libs)
      install(CODE "
        file(GET_RUNTIME_DEPENDENCIES
          RESOLVED_DEPENDENCIES_VAR deps
          ${executables} ${libraries}
          PRE_EXCLUDE_REGEXES
            \"^librt\.so\"
            \"^libdl\.so\"
            \"^libpthread\.so\"
            \"^libresolv\.so\"
            \"^libm\.so\"
            \"^libc\.so\"
        )
        file(INSTALL
          FILES \${deps}
          DESTINATION \${CMAKE_INSTALL_PREFIX}/lib
          FOLLOW_SYMLINK_CHAIN)
      ")
    endif()
  endforeach()
endfunction()
