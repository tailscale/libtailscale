#ifndef TAILSCALE_H
#define TAILSCALE_H

#ifdef __cplusplus
extern "C" {
#endif

extern void update_map(const char* key, const char* value);
extern int mira_start(void);

#ifdef __cplusplus
}
#endif

#endif
