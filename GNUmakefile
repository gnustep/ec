
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

# Information produced by autoconf
-include config.make

# Site specific overrides
-include ../local.make

PACKAGE_NAME=EnterpriseControlConfigurationLogging
PACKAGE_VERSION=1.1.3
Ec_INTERFACE_VERSION=1.1

SVN_BASE_URL=svn+ssh://svn.gna.org/svn/gnustep/libs
SVN_MODULE_NAME=ec

NEEDS_GUI=NO

# The libraries to be compiled
LIBRARY_NAME = ECCL

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
	EcTest.m \
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
	EcTest.h \
	EcUserDefaults.h \


TOOL_NAME = \
	Command \
	Console \
	Control \
	AlarmTool \
	LogTool \
	Terminate \


Command_OBJC_FILES = Command.m EcCommand.m EcClientI.m NSFileHandle+Printf.m
Command_TOOL_LIBS += -lECCL
Command_LIB_DIRS += -L./$(GNUSTEP_OBJ_DIR)

Console_OBJC_FILES = Console.m EcConsole.m NSFileHandle+Printf.m
Console_TOOL_LIBS += -lECCL
Console_LIB_DIRS += -L./$(GNUSTEP_OBJ_DIR)

Control_OBJC_FILES = Control.m EcControl.m EcClientI.m NSFileHandle+Printf.m
Control_TOOL_LIBS += -lECCL
Control_LIB_DIRS += -L./$(GNUSTEP_OBJ_DIR)

AlarmTool_OBJC_FILES = AlarmTool.m 
AlarmTool_TOOL_LIBS += -lECCL
AlarmTool_LIB_DIRS += -L./$(GNUSTEP_OBJ_DIR)
AlarmTool_CPPFLAGS += ${ECCL_CPPFLAGS}

LogTool_OBJC_FILES = LogTool.m 
LogTool_TOOL_LIBS += -lECCL
LogTool_LIB_DIRS += -L./$(GNUSTEP_OBJ_DIR)
LogTool_CPPFLAGS += ${ECCL_CPPFLAGS}

Terminate_OBJC_FILES = Terminate.m
Terminate_TOOL_LIBS += -lECCL
Terminate_LIB_DIRS += -L./$(GNUSTEP_OBJ_DIR)
Terminate_CPPFLAGS += ${ECCL_CPPFLAGS}



DOCUMENT_NAME = ECCL

ECCL_AGSDOC_FILES = ECCL.h \
	EcAlarm.h \
	EcAlarmDestination.h \
	EcAlarmSinkSNMP.h \
	EcAlerter.h \
        EcBroadcastProxy.h \
	EcHost.h \
	EcLogger.h \
	EcProcess.h \
	EcTest.h \
	EcUserDefaults.h \
	EcCommand.m \
	EcControl.m \
	EcConsole.m \

ECCL_AGSDOC_FLAGS = \
	-MakeFrames YES \


ECCL_DOC_INSTALL_DIR = Libraries


-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/library.make
include $(GNUSTEP_MAKEFILES)/tool.make
include $(GNUSTEP_MAKEFILES)/documentation.make

-include GNUmakefile.postamble
