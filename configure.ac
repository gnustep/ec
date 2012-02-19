dnl Process this file with autoconf to produce configure.

AC_INIT(EcProcess.h)
AC_CONFIG_HEADER(config.h)
AC_PROG_CC
AC_PROG_CPP

AC_CANONICAL_HOST

dnl start proper config checks
AC_TYPE_SIGNAL

AC_HEADER_STDC
AC_HEADER_TIME
AC_HEADER_SYS_WAIT
AC_CHECK_HEADERS(arpa/inet.h arpa/telnet.h netinet/in.h netdb.h pwd.h string.h fcntl.h sys/fcntl.h sys/file.h sys/resource.h sys/time.h sys/types.h sys/socket.h sys/signal.h stdlib.h unistd.h)

AC_TYPE_GETGROUPS
AC_TYPE_SIGNAL
AC_TYPE_MODE_T

AC_CHECK_FUNCS(getpid setpgid)

AC_ARG_WITH([readline],
  [AS_HELP_STRING([--with-readline],
    [support fancy command line editing @<:@default=check@:>@])],
    [],
    [with_readline=no])
          
LIBREADLINE=
  AS_IF([test "x$with_readline" = xyes],
    [AC_CHECK_LIB([readline], [main],
      [AC_SUBST([LIBREADLINE], ["-lreadline -lncurses"])
       AC_DEFINE([HAVE_LIBREADLINE], [1],
		 [Define if you have libreadline])
      ],
      [if test "x$with_readline" != xcheck; then
	 AC_MSG_FAILURE(
	   [--with-readline was given, but test for readline failed])
       fi
      ], -lncurses)])

AC_OUTPUT(config.make)


