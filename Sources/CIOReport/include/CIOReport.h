#ifndef CIOREPORT_H
#define CIOREPORT_H

#include <CoreFoundation/CoreFoundation.h>

// Prototipos de la librería privada IOReport (/usr/lib/libIOReport.dylib).
// Sin header público; declarados a mano como hacen macmon/stats/NeoAsitop.
// Sin sudo, sin entitlements. Solo distribución local (no App Store).

typedef struct IOReportSubscription* IOReportSubscriptionRef;
typedef int (^ioreportiterateblock)(CFDictionaryRef ch);

CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef group, CFStringRef subgroup,
                                            uint64_t a, uint64_t b, uint64_t c);
void IOReportMergeChannels(CFDictionaryRef a, CFDictionaryRef b, CFTypeRef reserved);
IOReportSubscriptionRef IOReportCreateSubscription(void *a, CFMutableDictionaryRef desired,
                                                   CFMutableDictionaryRef *subbed,
                                                   uint64_t channel_id, CFTypeRef b);
CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef sub,
                                      CFMutableDictionaryRef subbed, CFTypeRef a);
CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef prev, CFDictionaryRef cur, CFTypeRef a);

CFStringRef IOReportChannelGetGroup(CFDictionaryRef ch);
CFStringRef IOReportChannelGetSubGroup(CFDictionaryRef ch);
CFStringRef IOReportChannelGetChannelName(CFDictionaryRef ch);
CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef ch);
int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef ch, int32_t index);
int32_t IOReportStateGetCount(CFDictionaryRef ch);
CFStringRef IOReportStateGetNameForIndex(CFDictionaryRef ch, int32_t index);
int64_t IOReportStateGetResidency(CFDictionaryRef ch, int32_t index);

void IOReportIterate(CFDictionaryRef samples, ioreportiterateblock block);

// CFRelease no está disponible desde Swift; wrapper para liberar la
// suscripción de IOReport (OpaquePointer, fuera de ARC).
static inline void BtoReleaseIOReportSubscription(IOReportSubscriptionRef sub) {
    if (sub) CFRelease((CFTypeRef)sub);
}

#endif
