/*
 * http://lists.omnipotent.net/pipermail/lcdproc/2006-January/010417.html
 *
 * clang -framework Foundation -framework IOKit -o battery battery.c && ./battery
 */

/*
 * Copyright (c) 2003 Thomas Runge (coto@core.de)
 * Mach and Darwin specific code is Copyright (c) 2006 Eric Pooch (epooch@tenon.com)
 *
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the author nor the names of its contributors
 *    may be used to endorse or promote products derived from this
 *    software without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <sys/types.h>
#include <sys/param.h>
#include <sys/sysctl.h>
#include <sys/dkstat.h>
#include <sys/ucred.h>
#include <sys/mount.h>
#include <sys/time.h>
#include <sys/user.h>

#include <mach/mach.h>

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/ps/IOPSKeys.h>

extern int shellprompt_os_getpowerinfo(lua_State *L)
{
    CFTypeRef blob;
    CFArrayRef sources;
    CFDictionaryRef pSource;
    const void *psValue;
    int isbattery, ischarging, isdischarging, charge;
    int i;

    isbattery = ischarging = isdischarging = 0;
    charge = 100;
    blob = IOPSCopyPowerSourcesInfo();
    sources = IOPSCopyPowerSourcesList(blob);
    for (i = 0; i < CFArrayGetCount(sources); i++) {
        if (!(pSource = IOPSGetPowerSourceDescription(blob, CFArrayGetValueAtIndex(sources, i)))) {
            continue;
        }
        psValue = (CFStringRef)CFDictionaryGetValue(pSource, CFSTR(kIOPSNameKey));
        if (CFDictionaryGetValueIfPresent(pSource, CFSTR(kIOPSIsPresentKey), &psValue) &&
            (CFBooleanGetValue(psValue) > 0))
        {
            psValue = (CFStringRef)CFDictionaryGetValue(pSource, CFSTR(kIOPSPowerSourceStateKey));
            if (CFStringCompare(psValue, CFSTR(kIOPSBatteryPowerValue), 0) == kCFCompareEqualTo)
            {
                /* We are running on a battery power source. */
                isbattery = isdischarging = 1;
            }
            else if (CFDictionaryGetValueIfPresent(pSource, CFSTR(kIOPSIsChargingKey), &psValue))
            {
                /* We are running on an AC power source, but we also
                 * have a battery power source present. */
                isbattery = 1;
                ischarging = (CFBooleanGetValue(psValue) > 0);
            }
            if (*battflag != LCDP_BATT_ABSENT)
            {
                int curCapacity, maxCapacity, curPercent;
                curCapacity = maxCapacity = curPercent = 0;
                psValue = CFDictionaryGetValue(pSource, CFSTR(kIOPSCurrentCapacityKey));
                CFNumberGetValue(psValue, kCFNumberSInt32Type, &curCapacity);
                psValue = CFDictionaryGetValue(pSource, CFSTR(kIOPSMaxCapacityKey));
                CFNumberGetValue(psValue, kCFNumberSInt32Type, &maxCapacity);
                if ((maxCapacity > 0) && (curCapacity < maxCapacity)) {
                    curPercent = (100 * curCapacity) / maxCapacity;
                }
                if (charge > curPercent) {
                    charge = curPercent;
                }
            }
        }
    }
    CFRelease(blob);
    CFRelease(sources);	
    lua_createtable(L, 0, 0);
    lua_pushboolean(L, isbattery);
    lua_setfield(L, -2, "isbattery");
    lua_pushboolean(L, ischarging);
    lua_setfield(L, -2, "ischarging");
    lua_pushboolean(L, isdischarging);
    lua_setfield(L, -2, "isdischarging");
    lua_pushinteger(L, charge);
    lua_setfield(L, -2, "charge");
    return 1;
}
