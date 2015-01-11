# Hacking shellprompt #

## References ##

http://www.understudy.net/custom.html

http://tldp.org/HOWTO/Xterm-Title-4.html

https://en.wikipedia.org/wiki/Box-drawing_character

Linux console_codes(4) manual page

## Inspiration

http://aperiodic.net/phil/prompt/

http://en.tldp.org/HOWTO/Bash-Prompt-HOWTO/

https://bbs.archlinux.org/viewtopic.php?id=84386

"My Extravagant Zsh Prompt". Steve Losh. 2010-02-01.
http://stevelosh.com/blog/2010/02/my-extravagant-zsh-prompt/

Oh My Zsh
https://github.com/robbyrussell/oh-my-zsh

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
