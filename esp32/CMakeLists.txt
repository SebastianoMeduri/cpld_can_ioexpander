# Progetto ESP-IDF di esempio per l'I/O expander CAN.
# Build:  idf.py set-target esp32   &&   idf.py build flash monitor
cmake_minimum_required(VERSION 3.16)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(can_ioexpander_host)
