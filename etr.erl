-module(etr).
-export([start/0, start/1]).
-define(AGENT, "Mozilla/5.0").

start() ->
    start([files, "etr.sources", "etr.targets"]).

start([files, SourcesFile, TargetsFile]) ->
    Sources = setup(SourcesFile, fun(Line) -> list_to_tuple(string:tokens(Line, ";")) end),
    Targtes = setup(TargetsFile, fun(Line) -> Line end),
    start([lists, Sources, Targtes]);
start([lists, Sources, Targtes]) ->
    inets:start(),
    io:fwrite("Tracing (sources: ~w, targets: ~w): ", [length(Sources), length(Targtes)]),
    statistics(wall_clock),
    store(trace(Sources, {list, Targtes})),
    {_, Time} = statistics(wall_clock),
    io:fwrite("~nTime: ~.3f secs~n", [Time / 1000.0]).

trace(Sources, {item, Target}) ->
    plists:map(fun({Location, Server, Request}) ->
		   Route = case fetch(Server, Request, Target) of
			       {error, Reason} -> "Error: " ++ Reason;
			       {ok, Data} -> Data
			   end,
		   io:format(".", []),
		   {Location, Server, Route}
	       end,
	       Sources, 1);
trace(Sources, {list, Targets}) ->
    plists:map(fun(Target) ->
		   Route = trace(Sources, {item, Target}),
		   io:format("*", []),
		   {Target, Route}
	       end,
	       Targets, 1).

store({Target, Routes}) ->
    {ok, Dev} = file:open(Target ++ ".trc", write),
    lists:foreach(fun({Location, Server, Route}) ->
		      io:fwrite(Dev, "--- Route from ~s (~s) to ~s ---~n", [Location, Server, Target]),
		      io:fwrite(Dev, "~s~n", [Route]),
		      io:fwrite(Dev, "--- End ---~n", [])
		  end,
		  Routes),
    file:close(Dev);
store(Traces) ->
    lists:foreach(fun({Target, Routes}) ->
    		      store({Target, Routes})
		  end,
		  Traces).

setup(File, Fun) ->
    case file:open(File, read) of
	{error, Reason} ->
	    io:format("Error: can't open file \"~s\": [~p].~n", [File, Reason]),
	    exit({File, Reason});
	{ok, Dev} -> lines(Dev, Fun, [])
    end.

lines(Dev, Fun, List) ->
    case io:get_line(Dev, '') of
        eof  -> lists:reverse(List);
        Line -> lines(Dev, Fun, [Fun(string:strip(Line, right, $\n)) | List])
    end.

fetch(Server, Request, Target) ->
    Url = "http://" ++ Server ++ Request ++ Target,
    case http:request(get, {Url, [{"User-Agent", ?AGENT}]}, [], []) of
	{error, {connect_failed, Reason}}  -> {error, "connect failed: " ++ atom_to_list(Reason)};
	{error, Reason}                    -> {error, Reason};
	{ok, {{_, Code, Reason}, _, Body}} ->
	    case Code == 200 of
		false -> {error, Reason};
		true  -> parse(Body)
	    end
    end.

parse(Html) ->
    case re:run(Html, "<pre.*?>\\s*(.*?)\\s*(<|\\z)", [caseless, multiline, dotall, {capture, [1], list}]) of
	nomatch         -> {error, "invalid data"};
	{match, Result} -> {ok, re:replace(Result, "\\n\\s*\\n", "\n", [global, {newline, anycrlf}])}
    end.
