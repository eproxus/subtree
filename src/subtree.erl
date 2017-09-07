-module(subtree).

% API
-export([find/2]).
-export([get/2]).
-export([get/3]).
-export([set/3]).
-export([del/2]).
-export([deep_merge/1]).
-export([deep_merge/2]).

%--- API -----------------------------------------------------------------------

find(Path, Struct) when is_list(Path) ->
    search(Struct, Path, fun() -> undefined end);
find(Key, Struct) ->
    find([Key], Struct).

get(Path, Struct) when is_list(Path) ->
    search(Struct, Path, fun() -> error({key_not_found, Path}) end);
get(Key, Struct) ->
    get([Key], Struct).

get(Path, Struct, Default) when is_list(Path) ->
    search(Struct, Path, fun() -> Default end);
get(Key, Struct, Default) ->
    get([Key], Struct, Default).

set(Path, Value, Struct) when is_list(Path) ->
    recursive(Struct, Path, {set, Value});
set(Key, Value, Struct) ->
    set([Key], Value, Struct).

del(Path, Struct) when is_list(Path) ->
    recursive(Struct, Path, delete);
del(Key, Struct) ->
    del([Key], Struct).

deep_merge([Map|Maps]) -> deep_merge(Map, Maps).

deep_merge(Target, []) ->
    Target;
deep_merge(Target, [From|Maps]) ->
    deep_merge(deep_merge(Target, From), Maps);
deep_merge(Target, Map) when is_map(Map) ->
    % Key collisions prefer maps over normal values. If a map is to be written
    % to a key, a existing normal value is overwritten and an existing  map is
    % merged.
    maps:fold(
        fun(K, V, T) ->
            case maps:find(K, T) of
                {ok, Value} when is_map(Value), is_map(V) ->
                    maps:put(K, deep_merge(Value, V), T);
                {ok, Value} when is_map(Value) ->
                    T;
                {ok, _Value} ->
                    maps:put(K, V, T);
                error ->
                    maps:put(K, V, T)
            end
        end,
        Target,
        Map
    ).

%--- Internal ------------------------------------------------------------------

search(Struct, [], _Default) ->
    Struct;
search([Item|Struct], [{Field, Key}|Path] = All, Default) when is_map(Item) ->
    case maps:find(Field, Item) of
        {ok, Key}   -> search(Item, Path, Default);
        {ok, _}     -> search(Struct, All, Default);
        error       -> search(Struct, All, Default)
    end;
search(Struct, [Item|Path], Default) when is_map(Struct) ->
    case maps:find(Item, Struct) of
        {ok, Value} -> search(Value, Path, Default);
        error       -> Default()
    end;
search({Struct}, Path, Default) ->
    search(Struct, Path, Default);
search([{Fields} = Item|Struct], [{Field, Key}|Path], Default) ->
    case proplists:get_value(Field, Fields) of
        Key   -> search(Item, Path, Default);
        _Else -> search(Struct, [{Field, Key}|Path], Default)
    end;
search(Struct, [Key|Path], Default) when is_list(Struct) ->
    case lists:keyfind(Key, 1, Struct) of
        false        -> Default();
        {Key, Other} -> search(Other, Path, Default)
    end;
search(_Struct, _Path, Default) ->
    Default().

recursive(Struct, Path, Action) ->
    try
        rec(Struct, Path, Action)
    catch
        throw:not_found ->
            error({key_not_found, Path});
        throw:exists ->
            error({incompatible_path, Path})
    end.

rec(Struct, [Key], Action) when is_map(Struct) ->
    case maps:is_key(Key, Struct) of
        true ->
            case Action of
                delete -> maps:remove(Key, Struct);
                {set, Value} -> maps:update(Key, Value, Struct)
            end;
        false ->
            case Action of
                delete -> throw(not_found);
                {set, Value} -> maps:put(Key, Value, Struct)
            end
    end;
rec(Struct, [Key|Path], Action) when is_map(Struct) ->
    case maps:find(Key, Struct) of
        {ok, Value} ->
            maps:update(Key, rec(Value, Path, Action), Struct);
        error ->
            case Action of
                delete -> throw(not_found);
                {set, _Value} -> maps:put(Key, rec(#{}, Path, Action), Struct)
            end
    end;
rec({Struct}, Path, Action) ->
    {rec(Struct, Path, Action)};
rec([{Item}|Struct], [{Field, Key}] = Path, Action) ->
    case lists:keyfind(Field, 1, Item) of
        {Field, Key} ->
            case Action of
                delete        -> Struct;
                {set, Value} -> [Value|Struct]
            end;
        _ ->
            [{Item}|rec(Struct, Path, Action)]
    end;
rec([{Item}|Struct], [{Field, Key}|Rest] = Path, Action) ->
    case lists:keyfind(Field, 1, Item) of
        {Field, Key} -> [{rec(Item, Rest, Action)}|Struct];
        _            -> [{Item}|rec(Struct, Path, Action)]
    end;
rec([{Key, _Data}|Struct], [Key], Action) ->
    case Action of
        delete       -> Struct;
        {set, Value} -> [{Key, Value}|Struct]
    end;
rec([{Key, Data}|Struct], [Key|Path], Action) ->
    [{Key, rec(Data, Path, Action)}|Struct];
rec([Item|Struct], [{Field, Key}|Rest] = Path, Action) when is_map(Item) ->
    case {maps:find(Field, Item), Rest, Action} of
        {{ok, Key}, [], delete}       -> Struct;
        {{ok, Key}, [], {set, Value}} -> [Value|Struct];
        {{ok, Key}, _, _}             -> [rec(Item, Rest, Action)|Struct];
        {error, _, _}                 -> [Item|rec(Struct, Path, Action)]
    end;
rec([Item|Struct], Path, Action) ->
    [Item|rec(Struct, Path, Action)];
rec([], Path, Action) ->
    case {Path, Action} of
        {_, delete}                 -> throw(not_found);
        {[Key|Rest], {set, _Value}} -> [{Key, rec([], Rest, Action)}];
        {[], {set, Value}}          -> Value
    end;
rec(_Struct, _Path, _Action) ->
    throw(exists).
