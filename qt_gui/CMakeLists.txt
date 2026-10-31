cmake_minimum_required(VERSION 3.21)

project(ExpanderTesterQt VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick QuickControls2)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(ExpanderTesterQt
    main.cpp
)

qt_add_qml_module(ExpanderTesterQt
    URI ExpanderTester
    VERSION 1.0
    QML_FILES
        Main.qml
    SOURCES
        pcanbasic.h pcanbasic.cpp
        expandercontroller.h expandercontroller.cpp
)

set_target_properties(ExpanderTesterQt PROPERTIES
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(ExpanderTesterQt PRIVATE Qt6::Quick Qt6::QuickControls2)

# PCANBasic.dll (x64) e' caricato a runtime: se indicato con
# -DPCANBASIC_DLL=<percorso>, viene copiato accanto all'eseguibile.
set(PCANBASIC_DLL "" CACHE FILEPATH "Percorso di PCANBasic.dll (x64) da copiare accanto all'eseguibile")
if(PCANBASIC_DLL)
    add_custom_command(TARGET ExpanderTesterQt POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different "${PCANBASIC_DLL}" "$<TARGET_FILE_DIR:ExpanderTesterQt>"
        COMMENT "Copia di PCANBasic.dll")
endif()

include(GNUInstallDirs)
install(TARGETS ExpanderTesterQt
    BUNDLE  DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
if(PCANBASIC_DLL)
    install(FILES "${PCANBASIC_DLL}" DESTINATION ${CMAKE_INSTALL_BINDIR})
endif()

# Deploy delle librerie Qt (windeployqt) con "cmake --install"
qt_generate_deploy_qml_app_script(
    TARGET ExpanderTesterQt
    OUTPUT_SCRIPT deploy_script
)
install(SCRIPT ${deploy_script})
