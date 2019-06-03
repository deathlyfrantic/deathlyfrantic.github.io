+++
title = "A Failed Experiment in Data Structures"
date = 2018-08-19
+++

I recently wrote [tack](https://github.com/deathlyfrantic/tack), which is a recreation of [Gary Bernhardt's
Selecta](https://github.com/garybernhardt/selecta) in C. Selecta is great, and there's no reason not to use it. My
motivation for writing tack was the work itself; I wanted to implement a real tool in C and make it as fast as I
possibly could. I've accomplished my goal, at least for the time being: I don't think I can make tack any faster without
using threads. I may eventually try that, but for now I'm calling it done.

In my search for speed, I tried an experiment with an interesting data structure. It didn't quite work out, but it was a
fun journey.

## Background

Tack is a fuzzy finder. You dump some text into it through `stdin` and it opens up `/dev/tty` to display a UI which
allows you to search and filter the text. Once you've made a selection, tack outputs the line you chose to `stdout`.

The search algorithm in tack comes directly from Selecta. Imagine searching for the query `imc` in the line `this is my
sentence`. The search goes something like this:

1. tack searches through each character in the line and looks for a match for the `i` - in this case, it finds the `i`
   at position 2 (0-indexed)
2. if a match is found, it then looks for the `m`, starting from the letter after the `i` - in this case, starting from
   position 3, it finds the `m` at position 8
3. if a match is found, it then looks for the `c`, starting from the letter after the `m` - in this case, starting from
   position 9, it finds the `c` at position 17

The "score" for this match is 17 - 2 = 15.[^1] But we're not done! Now, tack searches through each character in the line
_starting from position 3_, looking for a match for the `i`, and finds one at position 5. The remaining behavior is the
same, but this time our score ends up being 17 - 5 = 12. Tack continues in this fashion, trying to find the lowest
score, by starting a search from every `i` in the line. In this case, the lowest score is 12, so that's the score we
use.

Every line is scanned in full at least once, searching for the first letter of the query, and then each sub-line is
scanned for every other letter in the query. The fastest scenario is the line contains none of the query letters - in
this case, we scan the line once and return `NULL` because there is no score. The second fastest scenario is the line
contains the first letter of the query, but none of the remaining - in this case, we scan the line once entirely, and
then once from the first letter match until the end, returning `NULL`. You can extrapolate the behavior. This can get
hairy if there are lots of matches and sub-lines to scan. I'm not great with big-O notation but I believe this is O(n
log n).

In our example, we looked at 47 characters:

- 19 in the full line, searching for every `i`
- 15 in the first match, from the `s` after the first `i` to the `c`
- 13 in the second match, from the `s` after the second `i` to the `c`

We found two matches of three characters each - so only six of the 47 were relevant. The rest were just wasted cycles.

## The Light Bulb

It seemed to me a lot of time is wasting looking at letters that _don't_ match; what if we could only search the letters
that do?

Imagine a data structure that looks something like this (shown in JSON for brevity):

    {
        "t": [0, 14],
        "h": [1],
        "i": [2, 5],
        "s": [3, 6, 11],
        " ": [4, 7, 10],
        "m": [8],
        "y": [9],
        "e": [12, 15, 18],
        "n": [13, 16],
        "t": [14],
        "c": [17],
    }

Essentially, it's a hash table of lists. With a structure like this, we could avoid characters we're not searching for
entirely! Instead, we'd look for a key first, to determine whether there are _any_ of the characters we want; if there
are, we can look at the positions of _just_ that character to figure out if it is part of our match.

This time:

1. we search for `i` in the keys of the table and find it is there, so we start our search at positions 2 and 5 (more
   accurately 3 and 6)
2. we search for `m` in the keys of the table and find it is there - only one, at position 8; this works for both
   matches
3. we search for `c` in the keys of the table and find it is there - only one, at position 17; this works for both
   matches

We never had to look at any letter that wasn't in our query! Instead of looking at 47 characters, we looked at 6.

Imagine searching this same line for `foo`: we immediately know `f` is not a key in our table, and we're done. Instead
of the O(n) performance of iterating at every character in the line, instead we get O(1) performance from looking up a
key in a hash table.[^2] We did one hash table lookup, instead of looking at 19 entire characters.

Now imagine searching for `ce`: we find `c` in the table once, at position 17. We then search for `e`, find it in three
positions - but only one after our `c`, which is position 18. In this case we looked at one `c` and three `e`s - four
total characters, and they were all contained within our query.

Ultimately I decided to call this structure a `CharMap`[^3].

## Implementation

I thought this had to be worth trying, so I did. There's a [branch on
GitHub](https://github.com/deathlyfrantic/tack/tree/charmap-experiment). Most of the action is in
[`charmap.c`](https://github.com/deathlyfrantic/tack/blob/charmap-experiment/src/charmap.c). I used the existing hash
table implementation that I had already written to cache search results and then a growable array structure (very
similar to what I had already written to store other list data) to store the positions of each character.

Surprisingly, it worked! This is by far the most complicated data structure I've ever implemented in C, and I was
pleased with myself for how quickly I managed to get it working.

Unfortunately, it didn't really help.

## The Problem

When using the existing algorithm, this data structure _does_ speed up searches. _However_, I hadn't factored in the
cost of setting up these structures in the first place. In tack, that cost is amortized over the life of the process,
since the input lines are essentially immutable. I had figured whatever the penalty was of setting up these structures
would be well worth the speed increase of the searching, and it just wasn't.

I didn't specifically measure, but search speed was not noticeably faster. Start-up time, though, skyrocketed. What used
to be a barely perceptible flicker of a pause when starting up turned into a painfully obvious halt while all of the
structures were allocated and filled.

## Trade-off

The general lifetime of a tack process is short. The idea is you dump some data in, enter a few characters to find the
line you want, maybe scroll up or down a few times, and hit enter. If you're a fast typist and know what you're looking
for, it may be running for less than a second total. In this context, the abysmal start-up time penalty imposed by the
`CharMap` structure was just too much to bear.

But, tack is generally used to operate on "short"[^4] lines. Searching a short line for a short query doesn't offer as
much opportunity for optimization as searching a long line for a long query. Depending on the length of the lines and
the query, it may be entirely reasonable to endure the increased start-up cost to save a lot of time searching.

There's probably a way to calculate the inflection point at which using this data structure makes sense, but I'm not
mathy enough to figure it out myself.

## Conclusion

While this experiment didn't pan out, I still feel it was useful to perform. It took me out of my comfort zone and
forced me to stretch my abilities. In writing tack, not only have I really explored some complicated data structures,
I've also learned how to use lldb to debug C, and how to profile a running process using Instruments.app.

I'm not expecting anyone to switch from Selecta to tack. Unless you only need ASCII support and regularly search
hundreds of thousands of lines, the increased speed will not help you. For me, the whole point of writing tack in the
first place was learning. By that measure, it has been a very successful project.

[^1]: The scoring is a little more complicated than this, but this simplified version captures the gist of it.

[^2]: Hash tables only _average_ O(1) performance, but in this case, since we're only dealing with ASCII, I used 255
buckets in the hash table and the ordinal value of the character as the hash; this way I was guaranteed to avoid
collisions.

[^3]: I'm sure someone else has come up with something like this before and given it a better name.

[^4]: For some definition of "short."
