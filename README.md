# findcmd
findcmd.pl - quickly find bash command using fuzzy patterns

If you remember you created/used command that sounds alike but do not remember exact spelling or whether it was alias/script/function/binary - this command is for you.

Note: The behaviour for collecting of aliases and functions from current shell has been changed. 
To use this script add alias findcmd to your ~/.bashrc:

<code>
alias findcmd='typeset -f >~/.functions;alias >~/.aliases;findcmd.pl -functions_file ~/.functions -aliases_file=~/.aliases'
</code>

<br>This should work without flaws.

It creates the list of all available commands at current login bash instance.

Then it looks over this list for specified patterns using fuzzy search.

It increments hits for list of all bash functions, aliases, bin files from  PATH by looking at their name and content for specified patterns. 
As search is fuzzy it might return a lot of results. To hit what you need you have to look at bottom of the list, as search count each hit with some weight and for each binary found it calculates total weight.
It  then lists names with non zero hits sorted by total hits incrementally (the best match goes bottom)

You can control resulting weight by using *weight* options.
       -soundex_weight 10       if pattern matches bin name using soundex algorithm it
                                adds 10 to hits on this bin.
                                If you don't want use soundex comparison use
                                -soundex_weight 0
       -regex_weight 20         if pattern matches bin name using regexp comparison it
                                adds 20 to hits on this bin
       -line_weight 1           for each line of bin that matches pattern regexp it
                                increments hits by 1.
                                If you don't want grepping over bin's lines use
                                -line_weight 0

Yes, it also looks for lines of script to match the specified patterns. But only for those that are specified using -path_for_script option and which size is not more than -max_script_size.

       -path_for_scripts ~/bin  Look for script lines only if script belongs to specified directories.
                                You can specify multiple pathes using
                                ":" delimiter in a way you do for regular PATH env variable.
       -max_script_size 1024        Maximal size of file that will be considered as script so it's lines will be examined.

