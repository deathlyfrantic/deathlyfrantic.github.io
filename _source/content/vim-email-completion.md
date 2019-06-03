+++
title = "Email Address Completion in Vim"
date = 2017-03-19
+++

A while back I somehow stumbled across [this Vim utility](https://arp242.net/code/complete_email.vim/) which provides a
completion function for email addresses. I really liked the idea, but I didn't love the implementation; I don't want to
create a new store for my contacts and I certainly don't want to have to use a special escape character to separate the
fields in that store. Instead, I decided to reimplement the idea to suit my needs.

My Mutt configuration looks something like this:

    $XDG_CONFIG_HOME/mutt
    ├── aliases.muttrc
    ├── colors.muttrc
    ├── default.muttrc -> $XDG_CONFIG_HOME/mutt/account1.muttrc
    ├── account1.muttrc
    ├── account2.muttrc
    ├── mailcap
    └── muttrc

I keep all of my configuration in `$XDG_CONFIG_HOME/mutt`[^1], and I separate different concerns into separate files. My
main `muttrc` then `source`s the other files as appropriate. My aliases go in `aliases.muttrc`, colors in
`colors.muttrc`, etc. I keep account settings in separate files, and then link one of those account files to
`default.muttrc`, so that I can use different accounts by default on different machines.

The point of all that explanation is: I already store my contacts in `aliases.muttrc`[^2], which Mutt can read and
update, and which can be easily-parsed. The general format of a Mutt alias is:

    alias foo Firstname Lastname <email@address.com>

The pieces here are:

- `alias` - this is the command itself
- foo - this is the short name I would type in Mutt to identify a given alias
- Firstname Lastname - really this is anything between the short name and the email address, but is generally a
  contact's proper name
- &lt;email@address.com&gt; - the email address itself, enclosed in angle brackets

Since this is a regular format[^3], it is easy to parse in a Vim completion function. Here's the whole function, but the
parsing bit is only the last three lines:

    function! emailcomplete#complete(findstart, base) abort
      if a:findstart
        " this portion finds and returns the starting
        " column of the word before the cursor
        let l:curpos = getcurpos()
        let l:pos = searchpos('\s', 'b')
        return (l:pos[0] == l:curpos[1]) ? l:pos[1] : 0
      endif
      " this portion finds aliases that contain the word
      " before the cursor and returns a list of them
      let aliases = readfile(expand('$XDG_CONFIG_HOME/mutt/aliases.muttrc'))
      let emails = filter(aliases, {_, alias -> substitute(alias, '^alias ', '', '') =~? a:base})
      return map(copy(emails), {_, alias -> substitute(alias, '^alias \w\+ ', '', '')})
    endfunction

Basically: read in the `aliases.muttrc` file as a list; filter that list so that it only contains lines where the
portion _after_ the `alias` command contains the matched string; return those results, but without the `alias shortname`
portion.

For example, let's say I have this alias set up for my mom:

    alias mom Firstname Lastname <firstname.lastname@mother.com>

The above function will find this alias regardless of whether I type "firstname" or "mother" or "mom" or anything else
contained in the string `mom Firstname Lastname <firstname.lastname@mother.com>`. But, it only _returns_ `Firstname
Lastname <firstname.lastname@mother.com>`, not `mom`. So, my `To:` header goes from this:

    To: mom

to this:

    To: Firstname Lastname <firstname.lastname@mother.com>

If you want to use this function, but you're unfamiliar with Vim completion, I'd recommend you read `:h ins-completion`.
That said, here's a basic tl;dr:

1. Save the above function in `$VIMHOME/autoload/emailcomplete.vim` (adjust the location of your aliases file as
   necessary)
2. Add `setlocal completefunc=emailcomplete#complete` to `$VIMHOME/ftplugin/mail.vim` -or- add `autocmd FileType mail
   setlocal completefunc=emailcomplete#complete` to your `$MYVIMRC`
3. Press <kbd>&lt;C-X&gt;&lt;C-U&gt;</kbd>[^4] in insert mode when you want to complete an email address in a mail file.

Voilà!

[^1]: Mutt supports `$XDG_CONFIG_HOME` by default [as of version 1.8](http://www.mutt.org/doc/UPDATING). Hoorah!

[^2]: Mutt has an [`$alias_file`](http://www.mutt.org/doc/manual/#alias-file) variable you can set, which is the default
location where it will save aliases.

[^3]: The alias command does support [some other syntax](http://www.mutt.org/doc/manual/#alias), but my usage of aliases
is pretty simple, so I only care about the basic syntax I explained.

[^4]: The [original implementation](https://github.com/Carpetsmoker/complete_email.vim) uses
<kbd>&lt;C-X&gt;&lt;C-M&gt;</kbd> for triggering the completion, but I'm fine using the standard user completion keys
for this. It's unlikely I'm going to have _another_ custom completion function for the mail filetype.
