#import <Foundation/Foundation.h>
#import <substrate.h>
#import <roothide.h>

#include <dirent.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <string>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

extern char **environ;

static thread_local unsigned int RHTranslationDepth = 0;

static bool RHHasPathPrefix(const char *path, const char *prefix) {
    if (path == nullptr || prefix == nullptr) return false;
    const size_t length = strlen(prefix);
    if (strncmp(path, prefix, length) != 0) return false;
    return path[length] == '\0' || path[length] == '/';
}

static bool RHShouldTranslatePath(const char *path) {
    if (path == nullptr || path[0] != '/') return false;

    // Never redirect Apple system, user-container or temporary paths.
    static const char *excluded[] = {
        "/System",
        "/private/var/mobile",
        "/private/var/containers",
        "/var/mobile",
        "/dev",
        "/tmp",
        "/private/tmp"
    };
    for (const char *prefix : excluded) {
        if (RHHasPathPrefix(path, prefix)) return false;
    }

    // Cydia/APT/bootstrap paths which live inside RootHide's randomised root.
    static const char *translated[] = {
        "/Applications/Cydia.app",
        "/Library/LaunchDaemons",
        "/Library/MobileSubstrate",
        "/Library/dpkg",
        "/bin",
        "/sbin",
        "/usr/bin",
        "/usr/sbin",
        "/usr/libexec",
        "/usr/share",
        "/etc/apt",
        "/etc/dpkg",
        "/etc/ssl",
        "/etc/alternatives",
        "/var/lib/apt",
        "/var/lib/dpkg",
        "/var/lib/cydia",
        "/var/cache/apt",
        "/var/cache/cydia",
        "/var/log/apt"
    };
    for (const char *prefix : translated) {
        if (RHHasPathPrefix(path, prefix)) return true;
    }
    return false;
}

static std::string RHTranslatedPath(const char *path) {
    if (path == nullptr) return std::string();
    if (RHTranslationDepth != 0 || !RHShouldTranslatePath(path)) {
        return std::string(path);
    }

    RHTranslationDepth++;
    const char *translated = jbroot(path);
    std::string result(translated != nullptr ? translated : path);
    RHTranslationDepth--;
    return result;
}

template <typename T>
static void RHInstallHook(const char *symbol, void *replacement, T *original) {
    void *address = dlsym(RTLD_DEFAULT, symbol);
    if (address != nullptr) {
        MSHookFunction(address, replacement, reinterpret_cast<void **>(original));
    }
}

static int (*RHOriginalOpen)(const char *, int, ...) = nullptr;
static int RHReplacementOpen(const char *path, int flags, ...) {
    mode_t mode = 0;
    const bool hasMode = (flags & O_CREAT) != 0;
    if (hasMode) {
        va_list arguments;
        va_start(arguments, flags);
        mode = static_cast<mode_t>(va_arg(arguments, int));
        va_end(arguments);
    }
    const std::string translated = RHTranslatedPath(path);
    return hasMode ? RHOriginalOpen(translated.c_str(), flags, mode)
                   : RHOriginalOpen(translated.c_str(), flags);
}

static int (*RHOriginalOpenAt)(int, const char *, int, ...) = nullptr;
static int RHReplacementOpenAt(int directory, const char *path, int flags, ...) {
    mode_t mode = 0;
    const bool hasMode = (flags & O_CREAT) != 0;
    if (hasMode) {
        va_list arguments;
        va_start(arguments, flags);
        mode = static_cast<mode_t>(va_arg(arguments, int));
        va_end(arguments);
    }
    const std::string translated = RHTranslatedPath(path);
    return hasMode ? RHOriginalOpenAt(directory, translated.c_str(), flags, mode)
                   : RHOriginalOpenAt(directory, translated.c_str(), flags);
}

static int (*RHOriginalCreat)(const char *, mode_t) = nullptr;
static int RHReplacementCreat(const char *path, mode_t mode) {
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalCreat(translated.c_str(), mode);
}

static FILE *(*RHOriginalFOpen)(const char *, const char *) = nullptr;
static FILE *RHReplacementFOpen(const char *path, const char *mode) {
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalFOpen(translated.c_str(), mode);
}

static FILE *(*RHOriginalFreopen)(const char *, const char *, FILE *) = nullptr;
static FILE *RHReplacementFreopen(const char *path, const char *mode, FILE *stream) {
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalFreopen(translated.c_str(), mode, stream);
}

static int (*RHOriginalAccess)(const char *, int) = nullptr;
static int RHReplacementAccess(const char *path, int mode) {
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalAccess(translated.c_str(), mode);
}

static int (*RHOriginalStat)(const char *, struct stat *) = nullptr;
static int RHReplacementStat(const char *path, struct stat *info) {
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalStat(translated.c_str(), info);
}

static int (*RHOriginalLStat)(const char *, struct stat *) = nullptr;
static int RHReplacementLStat(const char *path, struct stat *info) {
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalLStat(translated.c_str(), info);
}

static int (*RHOriginalMkdir)(const char *, mode_t) = nullptr;
static int RHReplacementMkdir(const char *path, mode_t mode) {
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalMkdir(translated.c_str(), mode);
}

static DIR *(*RHOriginalOpendir)(const char *) = nullptr;
static DIR *RHReplacementOpendir(const char *path) {
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalOpendir(translated.c_str());
}

static int (*RHOriginalUnlink)(const char *) = nullptr;
static int RHReplacementUnlink(const char *path) {
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalUnlink(translated.c_str());
}

static int (*RHOriginalRmdir)(const char *) = nullptr;
static int RHReplacementRmdir(const char *path) {
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalRmdir(translated.c_str());
}

static int (*RHOriginalRemove)(const char *) = nullptr;
static int RHReplacementRemove(const char *path) {
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalRemove(translated.c_str());
}

static int (*RHOriginalRename)(const char *, const char *) = nullptr;
static int RHReplacementRename(const char *source, const char *destination) {
    const std::string translatedSource = RHTranslatedPath(source);
    const std::string translatedDestination = RHTranslatedPath(destination);
    return RHOriginalRename(translatedSource.c_str(), translatedDestination.c_str());
}

static int (*RHOriginalChmod)(const char *, mode_t) = nullptr;
static int RHReplacementChmod(const char *path, mode_t mode) {
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalChmod(translated.c_str(), mode);
}

static int (*RHOriginalChown)(const char *, uid_t, gid_t) = nullptr;
static int RHReplacementChown(const char *path, uid_t owner, gid_t group) {
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalChown(translated.c_str(), owner, group);
}

static ssize_t (*RHOriginalReadlink)(const char *, char *, size_t) = nullptr;
static ssize_t RHReplacementReadlink(const char *path, char *buffer, size_t size) {
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalReadlink(translated.c_str(), buffer, size);
}

static int (*RHOriginalSymlink)(const char *, const char *) = nullptr;
static int RHReplacementSymlink(const char *target, const char *linkPath) {
    // Keep the stored target logical so it remains valid after RootHide changes root.
    const std::string translatedLink = RHTranslatedPath(linkPath);
    return RHOriginalSymlink(target, translatedLink.c_str());
}

static char *(*RHOriginalRealpath)(const char *, char *) = nullptr;
static char *RHReplacementRealpath(const char *path, char *resolvedPath) {
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalRealpath(translated.c_str(), resolvedPath);
}

static void *(*RHOriginalDlopen)(const char *, int) = nullptr;
static void *RHReplacementDlopen(const char *path, int mode) {
    if (path == nullptr) return RHOriginalDlopen(path, mode);
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalDlopen(translated.c_str(), mode);
}

static int (*RHOriginalPosixSpawn)(pid_t *, const char *, const posix_spawn_file_actions_t *,
                                   const posix_spawnattr_t *, char *const [], char *const []) = nullptr;
static int RHReplacementPosixSpawn(pid_t *pid, const char *path,
                                   const posix_spawn_file_actions_t *actions,
                                   const posix_spawnattr_t *attributes,
                                   char *const arguments[], char *const environment[]) {
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalPosixSpawn(pid, translated.c_str(), actions, attributes,
                                arguments, environment != nullptr ? environment : environ);
}

static int (*RHOriginalExecve)(const char *, char *const [], char *const []) = nullptr;
static int RHReplacementExecve(const char *path, char *const arguments[], char *const environment[]) {
    const std::string translated = RHTranslatedPath(path);
    return RHOriginalExecve(translated.c_str(), arguments,
                            environment != nullptr ? environment : environ);
}

static void RHPrepareEnvironment(void) {
    @autoreleasepool {
        NSString *bin = jbroot(@"/usr/bin");
        NSString *sbin = jbroot(@"/usr/sbin");
        NSString *rootBin = jbroot(@"/bin");
        NSString *rootSbin = jbroot(@"/sbin");
        NSString *existing = [[[NSProcessInfo processInfo] environment] objectForKey:@"PATH"] ?: @"/usr/bin:/bin";
        NSString *path = [NSString stringWithFormat:@"%@:%@:%@:%@:%@", bin, sbin, rootBin, rootSbin, existing];
        setenv("PATH", path.UTF8String, 1);
        setenv("CYDIA_ROOT_HIDE_COMPAT", "1", 1);
    }
}

__attribute__((constructor)) static void RHInitialiseCydiaCompatibility(void) {
    RHPrepareEnvironment();

    RHInstallHook("open", reinterpret_cast<void *>(&RHReplacementOpen), &RHOriginalOpen);
    RHInstallHook("openat", reinterpret_cast<void *>(&RHReplacementOpenAt), &RHOriginalOpenAt);
    RHInstallHook("creat", reinterpret_cast<void *>(&RHReplacementCreat), &RHOriginalCreat);
    RHInstallHook("fopen", reinterpret_cast<void *>(&RHReplacementFOpen), &RHOriginalFOpen);
    RHInstallHook("freopen", reinterpret_cast<void *>(&RHReplacementFreopen), &RHOriginalFreopen);
    RHInstallHook("access", reinterpret_cast<void *>(&RHReplacementAccess), &RHOriginalAccess);
    RHInstallHook("stat", reinterpret_cast<void *>(&RHReplacementStat), &RHOriginalStat);
    RHInstallHook("lstat", reinterpret_cast<void *>(&RHReplacementLStat), &RHOriginalLStat);
    RHInstallHook("mkdir", reinterpret_cast<void *>(&RHReplacementMkdir), &RHOriginalMkdir);
    RHInstallHook("opendir", reinterpret_cast<void *>(&RHReplacementOpendir), &RHOriginalOpendir);
    RHInstallHook("unlink", reinterpret_cast<void *>(&RHReplacementUnlink), &RHOriginalUnlink);
    RHInstallHook("rmdir", reinterpret_cast<void *>(&RHReplacementRmdir), &RHOriginalRmdir);
    RHInstallHook("remove", reinterpret_cast<void *>(&RHReplacementRemove), &RHOriginalRemove);
    RHInstallHook("rename", reinterpret_cast<void *>(&RHReplacementRename), &RHOriginalRename);
    RHInstallHook("chmod", reinterpret_cast<void *>(&RHReplacementChmod), &RHOriginalChmod);
    RHInstallHook("chown", reinterpret_cast<void *>(&RHReplacementChown), &RHOriginalChown);
    RHInstallHook("readlink", reinterpret_cast<void *>(&RHReplacementReadlink), &RHOriginalReadlink);
    RHInstallHook("symlink", reinterpret_cast<void *>(&RHReplacementSymlink), &RHOriginalSymlink);
    RHInstallHook("realpath", reinterpret_cast<void *>(&RHReplacementRealpath), &RHOriginalRealpath);
    RHInstallHook("posix_spawn", reinterpret_cast<void *>(&RHReplacementPosixSpawn), &RHOriginalPosixSpawn);
    RHInstallHook("execve", reinterpret_cast<void *>(&RHReplacementExecve), &RHOriginalExecve);

    // Install dlopen last because the hook installer itself uses dlsym.
    RHInstallHook("dlopen", reinterpret_cast<void *>(&RHReplacementDlopen), &RHOriginalDlopen);
}
