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


%% @doc Basic Actor utilities
-module(nkservice_actor_util).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-include("nkservice.hrl").
-include("nkservice_actor.hrl").
-include("nkservice_actor_debug.hrl").
-include_lib("nkevent/include/nkevent.hrl").

-export([send_external_event/3]).
-export([put_create_fields/1, update/2, check_links/2, do_check_links/2]).
-export([is_actor_id/1, actor_id_to_path/1]).
-export([make_path/1]).
-export([make_plural/1, make_singular/1, normalized_name/1]).
-export([fts_normalize_word/1, fts_normalize_multi/1]).
-export([update_check_fields/2]).


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Sends an out-of-actor event
-spec send_external_event(nkservice:id(), created|deleted|updated, #actor{}) ->
    ok.

send_external_event(SrvId, Reason, Actor) ->
    ?CALL_SRV(SrvId, actor_external_event, [SrvId, Reason, Actor]).


%% @doc Prepares an actor for creation
%% - uid is added
%% - name is added (if not present)
%% - metas creationTime, updateTime, generation and resourceVersion are added
put_create_fields(Actor) ->
    #actor{id=ActorId, metadata=Meta} = Actor,
    #actor_id{resource=Res, name=Name1} = ActorId,
    UID = make_uid(Res),
    %% Add Name if not present
    Name2 = case is_binary(Name1) of
        true ->
            case normalized_name(Name1) of
                <<>> ->
                    make_name(UID);
                NormName ->
                    NormName
            end;
        false ->
            make_name(UID)
    end,
    Time = nklib_date:now_3339(msecs),
    Actor2 = Actor#actor{
        id = ActorId#actor_id{uid=UID, name=Name2},
        metadata = Meta#{<<"creationTime">> => Time}
    },
    update(Actor2, Time).



%% @private
update(#actor{id=ActorId, data=Data, metadata=Meta}=Actor, Time3339) ->
    #actor_id{domain=Domain, group=Group, vsn=Vsn, resource=Res, name=Name} = ActorId,
    Gen = maps:get(<<"generation">>, Meta, -1),
    Hash = erlang:phash2({Domain, Group, Vsn, Res, Name, Data, Meta}),
    Meta2 = Meta#{
        <<"updateTime">> => Time3339,
        <<"generation">> => Gen+1
    },
    Actor#actor{hash=to_bin(Hash), metadata=Meta2}.


%% @doc
check_links(SrvId, #actor{metadata=Meta1}=Actor) ->
    case do_check_links(SrvId, Meta1) of
        {ok, Meta2} ->
            {ok, Actor#actor{metadata = Meta2}};
        {error, Error} ->
            {error, Error}
    end.


%% @private
do_check_links(SrvId, #{<<"links">>:=Links}=Meta) ->
    case do_check_links(SrvId, maps:to_list(Links), []) of
        {ok, Links2} ->
            {ok, Meta#{<<"links">>:=Links2}};
        {error, Error} ->
            {error, Error}
    end;

do_check_links(_SrvId, Meta) ->
    {ok, Meta}.


%% @private
do_check_links(_SrvId, [], Acc) ->
    {ok, maps:from_list(Acc)};

do_check_links(SrvId, [{Type, Id}|Rest], Acc) ->
    case nkservice_actor_db:find(SrvId, Id) of
        {ok, #actor_id{uid=UID}, _} ->
            true = is_binary(UID),
            do_check_links(SrvId, Rest, [{Type, UID}|Acc]);
        {error, actor_not_found} ->
            {error, linked_actor_unknown};
        {error, Error} ->
            {error, Error}
    end.


%% @doc Checks if ID is a path or #actor_id{}
%% SrvId must be an activated service, to check the service in the path
is_actor_id(#actor_id{}=ActorId) ->
    {true, ActorId};

is_actor_id(#actor{id=ActorId}) ->
    {true, ActorId};

is_actor_id(Path) when is_binary(Path); is_list(Path) ->
    case to_bin(Path) of
        <<$/, Path2/binary>> ->
            case binary:split(Path2, <<$/>>, [global]) of
                [Domain, Group, Res, Name] ->
                    ActorId = #actor_id{
                        domain = Domain,
                        group = Group,
                        resource = Res,
                        name = Name
                    },
                    {true, ActorId};
                _ ->
                    false
            end;
        _ ->
            false
    end.


%% @doc
actor_id_to_path(#actor_id{domain=Domain, group=Group, resource=Res, name=Name}) ->
    list_to_binary([$/, Domain, $/, Group, $/, Res, $/, Name]).


%% @private
make_path(Domain) ->
    case to_bin(Domain) of
        ?ROOT_DOMAIN ->
            <<>>;
        Domain2 ->
            Parts = lists:reverse(binary:split(Domain2, <<$.>>, [global])),
            nklib_util:bjoin(Parts, $.)
    end.


%% @private
make_uid(Kind) ->
    UUID = nklib_util:luid(),<<(to_bin(Kind))/binary, $-, UUID/binary>>.


%% @private
make_name(Id) ->
    UUID = case binary:split(Id, <<"-">>) of
        [_, Rest] when byte_size(Rest) >= 7 ->
            Rest;
        [Rest] when byte_size(Rest) >= 7 ->
            Rest;
        _ ->
            nklib_util:luid()
    end,
    normalized_name(binary:part(UUID, 0, 12)).


%% @private
normalized_name(Name) ->
    nklib_parse:normalize(Name, #{space=>$_, allowed=>[$+, $-, $., $_]}).


%% @private
make_plural(Type) ->
    Type2 = to_bin(Type),
    Size = byte_size(Type2),
    case binary:at(Type2, Size-1) of
        $s ->
            <<Type2/binary, "es">>;
        $y ->
            <<Type2:(Size-1)/binary, "ies">>;
        _ ->
            <<Type2/binary, "s">>
    end.


%% @private
make_singular(Resource) ->
    Word = case lists:reverse(nklib_util:to_list(Resource)) of
        [$s, $e, $i|Rest] ->
            [$y|Rest];
        [$s, $e, $s|Rest] ->
            [$s|Rest];
        [$s|Rest] ->
            Rest;
        Rest ->
            Rest
    end,
    list_to_binary(lists:reverse(Word)).


%% @private
fts_normalize_word(Word) ->
    nklib_parse:normalize(Word, #{unrecognized=>keep}).


%% @doc
fts_normalize_multi(Text) ->
    nklib_parse:normalize_words(Text, #{unrecognized=>keep}).


%% @doc
update_check_fields(NewActor, #actor_st{actor=OldActor, config=Config}) ->
    #actor{data=NewData} = NewActor,
    #actor{data=OldData} = OldActor,
    Fields = maps:get(immutable_fields, Config, []),
    do_update_check_fields(Fields, NewData, OldData).


%% @private
do_update_check_fields([], _NewData, _OldData) ->
    ok;

do_update_check_fields([Field|Rest], NewData, OldData) ->
    case binary:split(Field, <<".">>) of
        [Group, Key] ->
            SubNew = maps:get(Group, NewData, #{}),
            SubOld = maps:get(Group, OldData, #{}),
            case do_update_check_fields([Key], SubNew, SubOld) of
                ok ->
                    do_update_check_fields(Rest, NewData, OldData);
                {error, {updated_invalid_field, _}} ->
                    {error, {updated_invalid_field, Field}}
            end;
        [_] ->
            case maps:find(Field, NewData) == maps:find(Field, OldData) of
                true ->
                    do_update_check_fields(Rest, NewData, OldData);
                false ->
                    {error, {updated_invalid_field, Field}}
            end
    end.


%% @private
to_bin(T) when is_binary(T)-> T;
to_bin(T) -> nklib_util:to_binary(T).
