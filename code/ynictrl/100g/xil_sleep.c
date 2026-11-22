/******************************************************************************
* Copyright (c) 2014 - 2020 Xilinx, Inc.  All rights reserved.
* SPDX-License-Identifier: MIT
******************************************************************************/


/*****************************************************************************/
/**
* @file sleep.c
*
*  This header file contains ARM Cortex A53,A9,R5,Microblaze specific sleep
*  related APIs.
*
* <pre>
* MODIFICATION HISTORY :
*
* Ver   Who  Date	 Changes
* ----- ---- -------- -------------------------------------------------------
* 6.6   srm  11/02/17 Added processor specific sleep routines
*								 function prototypes.
*
* </pre>
*
******************************************************************************/

#include "xil_sleep_api.h"

#ifdef _WIN32
  void sleep(unsigned int seconds) {
    Sleep(seconds * 1000);
  }
  void usleep(unsigned long useconds) {
    Sleep(useconds / 1000);
  }
#endif
