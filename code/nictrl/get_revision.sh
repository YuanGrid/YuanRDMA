#!/bin/bash
REV=$(svn info --show-item last-changed-revision 2>/dev/null || echo "unknown")
echo "#ifndef SVN_REVISION_H" > version.h
echo "#define SVN_REVISION_H" >> version.h
echo "#define SVN_REVISION \"$REV\"" >> version.h
echo "#endif" >> version.h
