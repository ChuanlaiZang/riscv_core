# *********************************************************************************
# Project Name : DC Makefile
# Author       : Core_kingdom
# Website      : https://blog.csdn.net/weixin_40377195
# Create Time  : 2022-08-31
# File Name    : .v
# Module Name  :
# Called By    :
# Abstract     :
#
# 
# *********************************************************************************
# Modification History:
# Date         By              Version                 Change Description
# -----------------------------------------------------------------------
# 2022-08-31    Macro           1.0                     Original
#  
# *********************************************************************************


run :
	./scripts/gen_file.pl
	dc_shell -f scripts/dc_script.tcl | tee -i run.log

open:
	dv

clean :
	rm -rf *.log *.svf *.txt *.log
	rm -rf outputs reports
	rm -rf modules_list module_file.list files.tcl 
