/* Public domain */
/* luac should have an option to output in this format */

#include <stdio.h>
#include <stdlib.h>

#define PROGNAME "file2h"

static void dieif(const char *s, int failed)
{
    if (failed) {
        fprintf(stderr, "%s: error: %s\n", PROGNAME, s);
        exit(1);
    }
}

extern int main(int argc, char **argv)
{
    FILE *input;
    long n;
    int ch;

    dieif("usage", (argc != 3));
    dieif("fopen", !(input = fopen(argv[2], "rb")));
    dieif("fseek", fseek(input, 0, SEEK_END) != 0);
    dieif("ftell", (n = ftell(input)) == -1L);
    dieif("fseek", fseek(input, 0, SEEK_SET) != 0);
    dieif("printf", printf("static char %s[%ld] =\n", argv[1], n) < 0);
    n = 0;
    while ((ch = getc(input)) != EOF) {
        if (n % 16 == 0) {
            if (n) dieif("printf", printf("\"\n") < 0);
            dieif("printf", printf("\"") < 0);
        }
        dieif("printf", printf("\\x%02x", ch) < 0);
        n++;
    }
    dieif("printf", printf("\";\n") < 0);
    dieif("ferror", ferror(input));
    return 0;
}
