%% -------------------------------------------------------------------
%%
%% Copyright (c) 2018 Carlos Gonzalez Florido.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(nkservice_config_util).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([get_cache_map/1, get_cache_key/4, get_cache_key/5, set_cache_key/5, set_cache_map/2]).
-export([get_debug_map/1, get_debug_key/4, get_debug_key/5, set_debug_key/5, set_debug_map/2]).
-export([set_cache_items/4, set_debug_items/4]).


%% ===================================================================
%% Public
%% ===================================================================

%% @doc
get_cache_map(Spec) ->
    maps:get(cache_map, Spec, #{}).


%% @doc
get_cache_key(Group, Id, Key, CacheMap) ->
    get_cache_key(Group, Id, Key, CacheMap, undefined).


%% @doc
get_cache_key(Group, Id, Key, CacheMap, Default) ->
    maps:get({Group, Id, Key}, CacheMap, Default).


%% @doc
set_cache_key(Group, Id, Key, Value, CacheMap) ->
    CacheMap#{{Group, Id, Key} => Value}.


%% @doc
set_cache_map(CacheMap, Spec) ->
    Spec#{cache_map => CacheMap}.


%% @private
set_cache_items(Group, Id, Items, Spec) ->
    Cache1 = get_cache_map(Spec),
    Cache2 = maps:fold(
        fun(K, V, Acc) -> set_cache_key(Group, Id, K, V, Acc) end,
        Cache1,
        Items),
    nkservice_config_util:set_cache_map(Cache2, Spec).


%% @doc
get_debug_map(Spec) ->
    maps:get(debug_map, Spec, #{}).


%% @doc
get_debug_key(Group, Id, Key, DebugMap) ->
    get_debug_key(Group, Id, Key, DebugMap, undefined).


%% @doc
get_debug_key(Group, Id, Key, DebugMap, Default) ->
    maps:get({Group, Id, Key}, DebugMap, Default).


%% @doc
set_debug_key(Group, Id, Key, Value, DebugMap) ->
    DebugMap#{{Group, Id, Key} => Value}.


%% @doc
set_debug_map(DebugMap, Spec) ->
    Spec#{debug_map => DebugMap}.


%% @private
set_debug_items(Group, Id, Items, Spec) when is_map(Items) ->
    set_debug_items(Group, Id, maps:to_list(Items), Spec);

set_debug_items(Group, Id, Items, Spec) when is_list(Items) ->
    Cache1 = get_debug_map(Spec),
    Cache2 = lists:foldl(
        fun({K, V}, Acc) -> set_debug_key(Group, Id, K, V, Acc) end,
        Cache1,
        Items),
    nkservice_config_util:set_debug_map(Cache2, Spec).
