
ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
  ifeq ($(GNUSTEP_MAKEFILES),)
    $(warning )
    $(warning Unable to obtain GNUSTEP_MAKEFILES setting from gnustep-config!)
    $(warning Perhaps gnustep-make is not properly installed,)
    $(warning so gnustep-config is not in your PATH.)
    $(warning )
    $(warning Your PATH is currently $(PATH))
    $(warning )
  endif
endif

ifeq ($(GNUSTEP_MAKEFILES),)
  $(error You need to set GNUSTEP_MAKEFILES before compiling!)
endif

include $(GNUSTEP_MAKEFILES)/common.make

-include config.make
-include local.make

PACKAGE_NAME=EnterpriseControlConfigurationLogging
PACKAGE_VERSION=0.1.0
Ec_INTERFACE_VERSION=0.1

NEEDS_GUI=NO

# The library to be compiled
LIBRARY_NAME=ECCL

# The Objective-C source files to be compiled
ECCL_OBJC_FILES = \
	EcAlarm.m \
	EcAlarmDestination.m \
	EcAlarmSinkSNMP.m \
	EcAlerter.m \
	EcBroadcastProxy.m \
	EcHost.m \
	EcLogger.m \
	EcProcess.m \
	EcUserDefaults.m \

ECCL_HEADER_FILES = \
	EcAlarm.h \
	EcAlarmDestination.h \
	EcAlarmSinkSNMP.h \
	EcAlerter.h \
	EcBroadcastProxy.h \
	EcHost.h \
	EcLogger.h \
	EcProcess.h \
	EcUserDefaults.h \

TOOL_NAME = \
	Command \
	Console \
	Control \


Command_OBJC_FILES = Command.m Client.m NSFileHandle+Printf.m
Command_TOOL_LIBS += -lECCL
Command_LIB_DIRS += -L./$(GNUSTEP_OBJ_DIR)

Console_OBJC_FILES = Console.m NSFileHandle+Printf.m
Console_TOOL_LIBS += -lECCL
Console_LIB_DIRS += -L./$(GNUSTEP_OBJ_DIR)

Control_OBJC_FILES = Control.m Client.m NSFileHandle+Printf.m
Control_TOOL_LIBS += -lECCL
Control_LIB_DIRS += -L./$(GNUSTEP_OBJ_DIR)




DOCUMENT_NAME = ECCL

ECCL_AGSDOC_FILES = \
	EcAlarm.h \
	EcAlarmDestination.h \
	EcAlarmSinkSNMP.h \
	EcAlerter.h \
	EcHost.h \
	EcLogger.h \
	EcProcess.h \
	EcUserDefaults.h \


ECCL_DOC_INSTALL_DIR = Libraries


-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/library.make
include $(GNUSTEP_MAKEFILES)/tool.make
include $(GNUSTEP_MAKEFILES)/documentation.make

-include GNUmakefile.postamble
