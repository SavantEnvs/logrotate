/* Fuzzes logrotate's configuration-file parser (readAllConfigPaths -> readConfigFile).
 * config.c is included so the per-input cleanup can reach its static removeLogInfo(). */
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>

/* `createolddir` makes the parser mkdir() whatever path the input names. Fail only the parser's calls
 * (the macro applies to config.c alone) so an input cannot change the filesystem the next input sees;
 * the parser then takes its normal mkdir-error path. libFuzzer's own mkdir() (e.g. -fork's temp dir)
 * must keep working, so this is not a global override of the symbol. */
#define mkdir fuzz_mkdir
static int fuzz_mkdir(const char *path, mode_t mode)
{
    (void)path;
    (void)mode;
    errno = EACCES;
    return -1;
}
#include "../config.c"
#undef mkdir

#include <locale.h>

/* A private directory holds the input, so `include <dir>` from an input never sweeps up another
 * input's file, a sibling process's file, or this input's own file (which recursed without bound). */
static char scratchDir[PATH_MAX];
static char confPath[PATH_MAX];

static void removeScratch(void)
{
    unlink(confPath);
    rmdir(scratchDir);
}

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
    (void)argc;
    (void)argv;
    const char *tmpdir = getenv("TMPDIR");

    setlocale(LC_ALL, "C.UTF-8");
    snprintf(scratchDir, sizeof(scratchDir), "%s/logrotate-fuzz-XXXXXX", tmpdir && *tmpdir ? tmpdir : "/tmp");
    if (mkdtemp(scratchDir) == NULL)
        return -1;
    snprintf(confPath, sizeof(confPath), "%s/logrotate.conf", scratchDir);
    atexit(removeScratch);
    TAILQ_INIT(&logs);
    logSetLevel(MESS_FATAL + 1);
    logSetMessageFile(tmpfile());
    return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    const char *paths[2];
    struct logInfo *log;
    int fd;

    fd = open(confPath, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0)
        return 0;
    while (size > 0) {
        ssize_t n = write(fd, data, size);
        if (n <= 0)
            break;
        data += n;
        size -= (size_t)n;
    }
    close(fd);

    paths[0] = confPath;
    paths[1] = NULL;
    readAllConfigPaths(paths);
    unlink(confPath);

    /* readAllConfigPaths frees the taboo list but leaves these file-scope counters behind; a real run calls it once. */
    tabooPatterns = NULL;
    tabooCount = 0;

    while ((log = TAILQ_FIRST(&logs)) != NULL)
        removeLogInfo(log);
    return 0;
}
