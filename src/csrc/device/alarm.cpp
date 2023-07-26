/*上述代码是一个简单的闹钟/定时器功能的实现，包含以下主要内容：

头文件包含：代码中使用了一些系统标准库的头文件，包括 "common.h"、"device/alarm.h"、"sys/time.h" 和 "signal.h"。这些头文件提供了必要的函数和声明，以便实现闹钟功能。

宏定义：代码使用了一个宏定义 "#define MAX_HANDLER 8"，定义了最大的闹钟处理函数数量为 8。

全局变量和静态变量：代码定义了一个静态数组 "handler[MAX_HANDLER]"，用于存储闹钟处理函数。另外，还定义了一个静态变量 "idx"，用于跟踪当前已注册的闹钟处理函数数量。

add_alarm_handle 函数：该函数用于添加闹钟处理函数。它首先通过断言（assert）确保当前注册的处理函数数量未超过最大值，然后将新的处理函数添加到 "handler" 数组中。

alarm_sig_handler 函数：该函数是一个闹钟信号处理函数，当定时器触发信号（SIGVTALRM）时调用。它遍历 "handler" 数组，并依次调用其中的处理函数。

init_alarm 函数：该函数用于初始化闹钟功能。它首先设置了一个信号处理结构体 "s"，将其 sa_handler 成员设置为 "alarm_sig_handler" 函数。然后使用 sigaction 函数将 SIGVTALRM 信号与该处理结构体关联，以便在定时器触发时调用闹钟信号处理函数。

接下来，函数设置了一个定时器结构体 "it"，将其 it_value 成员设置为 0 秒和 1000000/TIMER_HZ 微秒（TIMER_HZ 是一个未定义的常量）。然后，使用 setitimer 函数将虚拟定时器 (ITIMER_VIRTUAL) 与该定时器结构体关联，以便按照设定的时间间隔触发定时器信号。

最后，函数使用断言检查信号处理和定时器设置是否成功。

以上是对代码的总结和概述，它实现了注册和触发闹钟处理函数的功能，并使用信号和定时器来实现定时触发。*/


#include <common.h>
#include <device/alarm.h>
#include <sys/time.h>
#include <signal.h>

#define MAX_HANDLER 8

static alarm_handler_t handler[MAX_HANDLER] = {};
static int idx = 0;

void add_alarm_handle(alarm_handler_t h) {
  assert(idx < MAX_HANDLER);
  handler[idx ++] = h;
}

static void alarm_sig_handler(int signum) {
  int i;
  for (i = 0; i < idx; i ++) {
    handler[i]();
  }
}

void init_alarm() {
  struct sigaction s;
  memset(&s, 0, sizeof(s));
  s.sa_handler = alarm_sig_handler;
  int ret = sigaction(SIGVTALRM, &s, NULL);
  Assert(ret == 0, "Can not set signal handler");

  struct itimerval it = {};
  it.it_value.tv_sec = 0;
  it.it_value.tv_usec = 1000000 / TIMER_HZ;
  it.it_interval = it.it_value;
  ret = setitimer(ITIMER_VIRTUAL, &it, NULL);
  Assert(ret == 0, "Can not set timer");
}
