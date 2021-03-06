(** {b JSIL annot}. *)
type t

(** Initialize an annotation *)
val init : ?line_offset: int option -> unit -> t

(** get the line offset *)
val get_line_offset : t -> int option

val line_info_to_str : (string * int * int) list -> string