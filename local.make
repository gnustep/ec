#
# This makefile is intended to allow site-local customisation of certain
# hard-coded defaults.  Edit it to suit your system if necessary.
#

# ECCL_CPPFLAGS ...
#
# EC_DEFAULTS_PREFIX
#   May be used to define an Objective-C string literal to be used as the
#   prefix when looking up keys in the defaults/configuration system.
#
# EC_DEFAULTS_STRICT
#   May be used to define an Objective-C boolean literal to be used to
#   control whether configuration keys are used only with the prefix
#   or whether values for keys without the prefix are also looked up.
#
# EC_EFFECTIVE_USER
#   May be used to define an Objective-C string literal to be used to
#   specify the name of the user to run all EcProcess programs.

ECCL_CPPFLAGS += \
	'-DEC_DEFAULTS_PREFIX=@"BS"'\
	'-DEC_DEFAULTS_STRICT=NO'\
	'-DEC_EFFECTIVE_USER=@"brains99"'\


