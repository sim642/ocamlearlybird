open Ground
open Errors

class virtual value =
  object
    method virtual to_short_string : string

    method num_indexed = 0

    method num_named = 0

    method get_indexed (_idx : int) : value Lwt.t = raise Index_out_of_bound

    method list_named : (string * value) list Lwt.t = Lwt.return []
  end

let uninitialized_value =
  object
    inherit value

    method to_short_string = "«uninitialized»"
  end

let unknown_value =
  object
    inherit value

    method to_short_string = "«opaque»"
  end

let adopters =
  ref
    ( []
      : (Scene.t ->
        Typenv.t ->
        Scene.obj ->
        Types.type_expr ->
        value option Lwt.t)
        list )

let adopt scene typenv obj ty =
  let rec resolve_type ty =
    match (Ctype.repr ty).desc with
    | Tlink ty | Tsubst ty | Tpoly (ty, _) -> resolve_type ty
    | Tconstr (path, ty_args, _) -> (
        match Typenv.find_type path typenv with
        | exception Not_found -> ty
        | {
         type_kind = Type_abstract;
         type_manifest = Some body;
         type_params;
         _;
        } -> (
            match Typenv.type_apply typenv type_params body ty_args with
            | ty -> resolve_type ty
            | exception Ctype.Cannot_apply -> ty )
        | _ -> ty )
    | _ -> ty
  in
  let ty = resolve_type ty in
  try%lwt
    !adopters |> List.to_seq
    |> Lwt_seq.find_map_s (fun adopter -> adopter scene typenv obj ty)
  with Not_found -> Lwt.return unknown_value