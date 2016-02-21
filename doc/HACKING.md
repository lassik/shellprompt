# Hacking shellprompt #

## Forth references ##

[Gforth manual](http://www.complang.tuwien.ac.at/forth/gforth/Docs-html/)

[Gforth manual -- list of words](http://www.complang.tuwien.ac.at/forth/gforth/Docs-html/Word-Index.html)

[ANS Forth standard -- list of words](https://www.taygeta.com/forth/dpansf.htm)

[ANS Forth standard -- table of contents](https://www.taygeta.com/forth/dpans.htm#toc)

## Terminal and shell references ##

[Bashish docs](http://bashish.sourceforge.net/doc.html) (Excellent reference)

[Eterm Technical Reference](http://www.eterm.org/docs/view.php?doc=ref) (Ditto. Thx Bashish!)

[Box-drawing character, Wikipedia](https://en.wikipedia.org/wiki/Box-drawing_character)

[Linux `console_codes(4)` manual page](http://linux.die.net/man/4/console_codes)

[Xterm 256 color names](http://jonasjacek.github.io/colors/)

[How to change the title of an xterm](http://tldp.org/HOWTO/Xterm-Title.html).
Ric Lister. v2.0. 1999-10-27

<http://www.understudy.net/custom.html>

## Inspiration ##

[Oh My Zsh](https://github.com/robbyrussell/oh-my-zsh)

[My Extravagant Zsh Prompt](http://stevelosh.com/blog/2010/02/my-extravagant-zsh-prompt/). Steve
Losh. 2010-02-01.

[Phil!'s ZSH Prompt](http://aperiodic.net/phil/prompt/). Phil! Gold.

[zer0prompt - a Phil!'s ZSH Prompt alternative for BASH users](https://bbs.archlinux.org/viewtopic.php?id=84386)

[Bashish is a theme enviroment for text terminals](http://bashish.sourceforge.net/screenshot.html)

[Bash Prompt HOWTO](http://en.tldp.org/HOWTO/Bash-Prompt-HOWTO/) Giles
Orr. Revision: 0.93. 2003/11/06.

## Known problems ##

### Line-drawing characters on Linux console ##

The Linux console doesn't properly display line drawing characters
from the VT100 graphics character set when a Unicode locale is
active. The horizontal line character gets displayed as the lowercase
letter "q" which resides at that same codepoint in the normal
codepage.

Quoting from <http://bytes.com/topic/python/answers/40973-line-graphics-linux-console>

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
