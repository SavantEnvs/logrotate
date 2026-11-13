/* Fuzzes logrotate's state-file parser (readState). logrotate.c is included so the harness can
 * reach the static parser and release its hash table between inputs. */
#define main logrotate_main
#include "../logrotate.c"
#undef main

#include <locale.h>

static void freeStates(void)
{
    unsigned int i;

    if (states == NULL)
        return;
    for (i = 0; i < hashSize; i++) {
        struct logState *p;

        if (states[i] == NULL)
            continue;
        while ((p = LIST_FIRST(&states[i]->head)) != NULL) {
            LIST_REMOVE(p, list);
            free(p->fn);
            free(p);
        }
        free(states[i]);
    }
    free(states);
    states = NULL;
    hashSize = 0;
}

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
    (void)argc;
    (void)argv;
    setlocale(LC_ALL, "C.UTF-8");
    TAILQ_INIT(&logs);
    logSetLevel(MESS_FATAL + 1);
    logSetMessageFile(tmpfile());
    return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    const char *tmpdir = getenv("TMPDIR");
    char path[PATH_MAX];
    int fd;

    snprintf(path, sizeof(path), "%s/logrotate-fuzz-XXXXXX", tmpdir && *tmpdir ? tmpdir : "/tmp");
    fd = mkstemp(path);
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

    debug = 0;
    readState(path);
    unlink(path);
    freeStates();
    return 0;
}
