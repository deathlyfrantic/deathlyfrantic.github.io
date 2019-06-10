+++
title = "vimlfmt"
date = 2019-06-09
+++

I've just made public the repo for a project I've been working on for quite a while -
[vimlfmt](https://github.com/deathlyfrantic/vimlfmt). vimlfmt is a code formatter for VimL (or VimScript) code, which is
the scripting language used by the Vim and Neovim text editors.

## Background

I love code formatters. It's not that I'm unable to format code myself - I am, and I care a lot about this kind of
thing. But formatting code is a pretty mechanical task, and mechanical tasks should be done by machines. I've seen
arguments against using formatters suggesting that doing it manually is somehow more pure or virtuous, but I think that
idea is silly. Your editor indents your code as you type, doesn't it? How is this different? Indeed, if all code
formatters did was indenting, I'd be ambivalent about the concept at best. But good formatters also deal with structure,
and that is where I see the value.

At work I write JavaScript almost exclusively, and [Prettier](https://prettier.io) is godsend. Essentially all
JavaScript that does anything useful has some level of complicated nesting going on. Take this example:

    const someVariable = someReallyLongFunctionName(foo, [bar, "baz"], { a: 1, b: 2, c: 3 }, err => console.log(err));

This line is 114 characters long, so if you're trying to keep to 80- or 100-character columns, it has to be broken
somewhere. Where do you break it? You may have some general rule you try to follow, but do you always follow it
consistently, in every case? Prettier does. It does this (with `--parser babylon --trailing-comma es5`):

    const someVariable = someReallyLongFunctionName(
      foo,
      [bar, "baz"],
      { a: 1, b: 2, c: 3 },
      err => console.log(err)
    );

And it does so for everyone, in every case. Now I don't have to go look for some other example that roughly matches the
shape of this code to see how it was formatted before. It's just done and I can move on with my life. And our projects
have consistent formatting no matter who works on them!

Even easier, I use [Neoformat](https://github.com/sbdchd/neoformat) and have Neovim set up to run Neoformat on save - so
every time I write a buffer, the code is formatted for me automatically. It's completely painless, and I'm so accustomed
to it I don't even notice when it happens.

## vimlfmt

Unfortunately, there was not a formatter for VimL code, or at least I was not able to find one. Since I (sadly) write a
fair amount of VimL, this was annoying. So, I decided I'd try to write one!

Since Rust has become my go-to language, I started there. I first toyed around with parsing VimL using a PEG parser
(specifically [rust-peg](https://github.com/kevinmehall/rust-peg)) but quickly ran into complications. First, I can't
say I thoroughly understand how to use a PEG parser; second, VimL is a hilariously complicated monstrosity of a
language, and I don't know if a PEG parser even _can_ parse VimL.

I then stumbled across an existing VimL parser, [vim-jp/vim-vimlparser](https://github.com/vim-jp/vim-vimlparser), which
is written in VimL itself (and also has ports to Python and JavaScript in the repo). I decided it might be a fun project
to port this parser to Rust, [which I did](https://github.com/deathlyfrantic/vimlfmt/tree/master/parser), in a
more-or-less line-by-line fashion from the Python version. (I've since done some cleanup/refactoring but it still very
much shows its roots as a translation.)

Once I had the parser basically working, I added a formatter layer on top, and the result is vimlfmt.

## VimL is a Terrible Language

Once I had a basic skeleton of a formatter working, I set about to add the pieces necessary to do formatting beyond just
basic indentation and line-length stuff. This is when I came upon the realization that VimL is a terrible language. On
the surface, it's basically Ruby- or Python-like - it's dynamic, there are no curly braces, in general it's pretty easy
to understand and read. Below that, however, it's a mess.

The basic building block of VimL's grammar[^1] is the expression, but to do almost anything useful, you need to use a
command. A command is either a built-in command (these start with lowercase letters, e.g. `echo`), or a user-defined
command (these must start with uppercase letters, e.g. `MyCommand`). This isn't inherently bad, but let's take a look at
an example which will illustrate one of the major pain points of parsing VimL.

Say you want to parse the `echo` command. If you look at `:help echo`, you'll see that `echo` takes one or more `expr1`
arguments. (An `expr1` has a specific definition in VimL which I will not explain here, but `:help expr1` goes into
depth.) So we can pass a string literal to `echo`, or we can pass some more complicated expression which will be
evaluated before the result is then echoed. Thus,

    echo "3 + 2 =" 3 + 2

will echo "3 + 2 = 5". Neat. This seems to make sense. A command is parsed as a name followed by some number of
space-separated expressions. Got it.

Now I want to change the way strings are highlighted, so I want to use the `highlight` command. Let's figure out how it
works. Probably I just need to pass the expressions in a certain order, right? Problem #1: `:help highlight` doesn't
take us directly to the `highlight` command; instead it takes us to the "Highlight command" section. Ok, scroll down,
find `:highlight`. At the time of this writing, the Neovim help lists _six_ different forms of the `:highlight`
command:

    :hi[ghlight]        List all the current highlight groups that have
                        attributes set.

    :hi[ghlight] {group-name}
                        List one highlight group.

    :hi[ghlight] clear  Reset all highlighting to the defaults.  Removes all
                        highlighting for groups added by the user!
                        Uses the current value of 'background' to decide which
                        default colors to use.

    :hi[ghlight] clear {group-name}
    :hi[ghlight] {group-name} NONE
                        Disable the highlighting for one highlight group.  It
                        is _not_ set back to the default colors.

    :hi[ghlight] [default] {group-name} {key}={arg} ..
                        Add a highlight group, or change the highlighting for
                        an existing group.
                        See highlight-args for the {key}={arg} arguments.
                        See :highlight-default for the optional [default]
                        argument.

This one command does many different things depending on the arguments I pass to it. Not only that, but the arguments
aren't expressions - they're just raw strings. Some of them, like `clear`, are flags, some of them, like `{group-name}`,
are variables, some of them are key-value pairs (`{key}={arg}`). So if you want to parse `highlight` commands, you have
to recognize this command and parse its own weird syntax specifically. But it's a command, just like `echo` - shouldn't
the syntax be the same?

(Another fun thing, while we're here - notice the "`hi[ghlight]`" in the help text there? What's that about? Vim allows
you to abbreviate commands to the shortest-possible unique substring, so you can use `:hi` or `:hig` or `:high` or
`:highl` etc instead of typing out `:highlight`. This is presumably meant for usability when typing commands in the
command line, but unfortunately it means you have to match, in the case of `highlight`, eight different strings to a
single command. Different plugins use different conventions - personally I always try to use the full command name, but
[CtrlP](http://github.com/ctrlpvim/ctrlp.vim) uses the shortest possible names, which I find basically unreadable.)

As we've just illustrated, parsing VimL commands is a huge pain. You need to account for every built-in command and its
unique syntax. Sure, some of them are the same: `echo`, `echon`, `echomsg`, and `echoerr` all use the same syntax
(though `echohl` doesn't!), but `highlight` has six different forms by itself. (Good luck figuring out `:syntax`!)

In some cases, differing syntax for commands makes sense: `let`, which is used for variable declaration, understandably
has a different syntax than `while`, which is the command used to begin a while loop. But there should be an upper bound
on this variability. The current state is obviously a result of Vim's long history, during which new functionality has
gradually been glommed on to the existing language, with little thought given to an overall design or consistency. Some
commands take arguments with sigils, e.g. `edit` takes options with a leading `++`, while others just take raw strings
as flags, e.g. our `highlight clear` example above, or `nested` in `autocmd`.

## Burnout

The longer I worked on the formatter, the more frustrated I became by VimL's weird quirks.[^2] This was partly
exacerbated by the fact that I was working in Rust, which (in my opinion) has a beautifully consistent design. I'd try
to implement formatting for a new command, and have to spend hours looking at the Vim help, working through all the
permutations. It was just exhausting.

Eventually I settled on making the parser dumber, and just parsing most commands as a name and a raw string for the
arguments. The idea is to move the parsing of the raw string of arguments into the consumer of the parsed tree (in
vimlfmt's case, the formatter portion). So that's where I've settled. But, I'm tired.

The fact is, I don't write nearly the amount of VimL I once did - my Vim environment is more-or-less feature complete,
and my general tendency these days is to remove plugins, rather than to add them. With this just being a private
project to which only I was contributing, progress stalled and eventually stopped. I haven't made significant changes to
the code in months. So this isn't the perfect time to "release" the project, but without external motivation, further
progress is unlikely.

## Contributions Wanted

I'd love for vimlfmt to become useful for people, and for others to be excited about it. I'd especially love
contributions from folks who know how to write code formatters - I'm very much just winging it, and it's entirely
possible the whole architecture of the project is terrible. If you would like to get involved, please do! Use it, see
what doesn't work or what could work better, and submit an issue or PR.

[^1]: I am not a programming language grammarian, so please forgive my imprecise usage of this term.

[^2]: At some point I made a more-than-trivial effort to switch over to Emacs, just to have a more reasonable scripting
  language. It didn't work out, because Vim's idioms are too ingrained in me to make such an effort worthwhile. (And
  before you try to argue with me about this: yes, I used Evil mode. It's not just modal keybindings for basic editing
  that keeps me using Vim.)
