# Hacking shellprompt #

## Testing ##

    build-osx/shellprompt set goo "bar \" baz" 'gaz a' aaa3 \' x
    build-osx/shellprompt set cyan host green sign sp
    build-osx/shellprompt encode

## References ##

http://www.understudy.net/custom.html

http://tldp.org/HOWTO/Xterm-Title-4.html

https://en.wikipedia.org/wiki/Box-drawing_character

Linux console_codes(4) manual page

## Known problems ##

### Line-drawing characters on Linux console ##

The Linux console doesn't properly display line drawing characters
from the VT100 graphics character set when a Unicode locale is
active. The horizontal line character gets displayed as the lowercase
letter "q" which resides at that same codepoint in the normal
codepage.

Quoting from http://bytes.com/topic/python/answers/40973-line-graphics-linux-console

> If you call up the minicom menu, it should be surrounded by a nice
> box made up of horizontal and vertical lines, corners, etc. It used to
> work up until Redhat 7. Since upgrading to Redhat 9, and now Fedora,
> it (and my program) has stopped working."
> 
> I received the following reply from Thomas Dickey -
> 
> "That's because Redhat uses UTF-8 locales, and the Linux console
> ignores vt100 line-drawing when it is set for UTF-8. (screen also
> does this).  ncurses checks for $TERM containing "linux" or "screen"
> (since there's no better clues for the breakage) when the encoding is
> UTF-8, and doesn't try to use those escapes (so you would get +'s and
> -'s).  compiling/linking with libncursesw would get the lines back
> for a properly-written program."
