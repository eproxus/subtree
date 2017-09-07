-module(subtree_tests).

-include_lib("eunit/include/eunit.hrl").

-import(subtree, [find/2, get/2, get/3, set/3, del/2, deep_merge/1]).

%--- Data ----------------------------------------------------------------------

-define(MAP, #{
    key => 0,
    proplist => [
        {proplist_map, #{
            key => 1
        }}
    ],
    map => #{
        map_proplist => {[
            {key, 2}
        ]}
    },
    list => [
        {[{key, "3"}, {value, 3}]},
        #{key => "4", value => 4}
    ],
    object => {[
        {key, 5}
    ]}
}).

-define(SINGLE_VALUE_PATHS, [
    {key,      0},
    {list,     [{[{key, "3"}, {value, 3}]}, #{key => "4", value => 4}]},
    {proplist, [{proplist_map, #{key => 1}}]},
    {map,      #{map_proplist => {[{key, 2}]}}}
]).

-define(VALUE_PATHS, [
    {[key],                         0},
    {[proplist, proplist_map, key], 1},
    {[map, map_proplist, key],      2},
    {[list, {key, "3"}, value],     3},
    {[list, {key, "4"}, value],     4},
    {[object, key],                 5}
]).

-define(STRUCT_PATHS, [
    {[proplist],               [{proplist_map, #{key => 1}}]},
    {[proplist, proplist_map], #{key => 1}},
    {[map],                    #{map_proplist => {[{key, 2}]}}},
    {[map, map_proplist],      {[{key, 2}]}},
    {[list],                   [{[{key, "3"}, {value, 3}]}, #{key => "4", value => 4}]},
    {[object],                 {[{key, 5}]}}
]).

-define(OVERWRITE_PATHS, [
    {[list, {key, "3"}], {[{key, "3"}, {value, 3}]}},
    {[list, {key, "4"}], #{key => "4", value => 4}}
]).

-define(READ_PATHS, ?VALUE_PATHS ++ ?STRUCT_PATHS ++ ?OVERWRITE_PATHS).

-define(WRITE_PATHS, ?VALUE_PATHS ++ ?STRUCT_PATHS).

%--- Tests ---------------------------------------------------------------------

parallel_test_() ->
    {inparallel, [
        fun find_/0,
        fun get_/0,
        fun get_missing_/0,
        fun get_empty_path_/0,
        fun set_/0,
        fun set_overwrite_/0,
        fun set_missing_/0,
        fun set_incompatible_/0,
        fun del_/0,
        fun del_missing_/0,
        fun del_incompatible_/0,
        fun deep_merge_/0
    ]}.

find_() ->
    [
        ?assertEqual(Value, find(Path, ?MAP))
        || {Path, Value} <- ?READ_PATHS ++ ?SINGLE_VALUE_PATHS
    ],
    ?assertEqual(undefined, find([proplist, missing], ?MAP)).

get_() ->
    [
        ?assertEqual(Value, get(Path, ?MAP))
        || {Path, Value} <- ?READ_PATHS ++ ?SINGLE_VALUE_PATHS
    ].

get_missing_() ->
    [
        begin
            Missing = Path ++ Addition,
            ?assertError({key_not_found, Missing}, get(Missing, ?MAP)),
            ?assertEqual(default, get(Missing, ?MAP, default))
        end
        || {Path, _} <- ?READ_PATHS, Addition <- [[missing], [{key, missing}]]
    ],
    ?assertError({key_not_found, [missing]}, get([missing], ?MAP)),
    ?assertEqual(default, get([missing], ?MAP, default)),
    ?assertError({key_not_found, [missing]}, get(missing, ?MAP)),
    ?assertEqual(default, get(missing, ?MAP, default)).

get_empty_path_() ->
    ?assertEqual(?MAP, get([], ?MAP)).

set_() ->
    [
        begin
            Map = set(Path, new, ?MAP),
            ?assertEqual(new, get(Path, Map))
        end
        || {Path, _} <- ?WRITE_PATHS ++ ?SINGLE_VALUE_PATHS
    ].

set_overwrite_() ->
    [
        begin
            Map = set(Path, new, ?MAP),
            ?assertError({key_not_found, Path}, get(Path, Map))
        end
        || {Path, _} <- ?OVERWRITE_PATHS
    ].

set_missing_() ->
    [
        begin
            New = [Path] ++ Addition,
            Map = set(New, new, ?MAP),
            ?assertEqual(new, get(New, Map))
        end
        || {Path, _} <- ?STRUCT_PATHS, Addition <- [[missing], [missing, sub]]
    ].

set_incompatible_() ->
    [
        begin
            New = Path ++ [subkey],
            ?assertError({incompatible_path, New}, set(New, new, ?MAP))
        end
        || {Path, _} <- ?VALUE_PATHS
    ].

del_() ->
    [
        begin
            Map = del(Path, ?MAP),
            ?assertError({key_not_found, Path}, get(Path, Map))
        end
        || {Path, _} <- ?READ_PATHS
    ].

del_missing_() ->
    [
        begin
            Missing = Path ++ [missing],
            ?assertError({key_not_found, Missing}, del(Missing, ?MAP))
        end
        || {Path, _} <- ?STRUCT_PATHS
    ],
    ?assertError({key_not_found, [missing]}, del([missing], ?MAP)),
    ?assertError({key_not_found, [missing]}, del(missing, ?MAP)).

del_incompatible_() ->
    [
        begin
            New = Path ++ [subkey],
            ?assertError({incompatible_path, New}, del(New, ?MAP))
        end
        || {Path, _} <- ?VALUE_PATHS
    ].

deep_merge_() ->
    Maps = [
        #{first  => 1, same => removed},
        #{second => 2, same => #{2 => true, samesame => #{more => stuff}}},
        #{third  => 3, same => #{3 => true, samesame => removed}},
        #{fourth => 4, same => #{4 => true, samesame => #{extra => data}}}
    ],
    Expected = #{
        first  => 1,
        second => 2,
        third  => 3,
        fourth => 4,
        same => #{
            2 => true,
            3 => true,
            4 => true,
            samesame => #{more => stuff, extra => data}
        }
    },
    ?assertEqual(Expected, deep_merge(Maps)).
