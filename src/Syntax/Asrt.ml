open SCommon
open CCommon
open SVal

(** {b JSIL logic assertions}. *)
type t =
  | Emp                                       (** Empty heap             *)
  | Star         of t * t                     (** Separating conjunction *)
  | PointsTo     of Expr.t * Expr.t * Expr.t  (** Heap cell assertion    *)
  | MetaData     of Expr.t * Expr.t           (** MetaData               *)
  | Pred         of string * (Expr.t list)    (** Predicates             *)
  | EmptyFields  of Expr.t * Expr.t           (** emptyFields assertion  *)
  | Pure         of Formula.t                 (** Pure formula           *)
  | Types        of (Expr.t * Type.t) list    (** Typing assertion       *)
     

let compare x y = 
  let cmp = Pervasives.compare in 
  (match x, y with 
  | Pure (Eq (PVar x, _)), Pure (Eq (PVar y, _)) -> cmp x y
  | Pure (Eq (PVar x, _)), _ -> -1
  | _, Pure (Eq (PVar x, _)) -> 1
  | PointsTo _, PointsTo _ -> cmp x y
  | PointsTo _, _ -> -1
  | _, PointsTo _ -> 1
  | MetaData _, MetaData _ -> cmp x y
  | MetaData _, _ -> -1
  | _, MetaData _ -> 1
  | EmptyFields _, EmptyFields _ -> cmp x y
  | EmptyFields _, _ -> -1
  | _, EmptyFields _ -> 1
  | Pure _, Pure _ -> cmp x y
  | Pure _, _ -> -1
  | _, Pure _ -> 1
  | Types _, Types _ -> cmp x y
  | Types _, _ -> -1
  | _, Types _ -> 1
  | Pred _, Pred _ -> cmp x y
  | Pred _, _ -> -1
  | _, Pred _ -> 1
  | _, _ -> cmp x y)

module MyAssertion =
  struct
    type nonrec t = t
    let compare = Pervasives.compare
  end

module Set = Set.Make(MyAssertion)

(** Apply function f to the logic expressions in an assertion, recursively when f_a returns (new_asrt, true). *)
let rec map
    (f_a_before  : (t -> t * bool) option)
    (f_a_after   : (t -> t) option)
    (f_e         : (Expr.t -> Expr.t) option)
    (f_p         : (Formula.t -> Formula.t) option)
    (a           : t) : t =

  (* Map recursively to assertions and expressions *)
  let map_a      = map f_a_before f_a_after f_e f_p in
  let map_e      = Option.default (fun x -> x) f_e in
  let map_p      = Option.default (Formula.map None None (Some map_e)) f_p in
  let f_a_before = Option.default (fun x -> x, true) f_a_before in 
  let f_a_after  = Option.default (fun x -> x) f_a_after in 
  let (a', recurse) = f_a_before a in 

    if not recurse then a' else ( 
      let a'' =
        match a' with
        | Star (a1, a2)                 -> Star (map_a a1, map_a a2)
        | PointsTo (e1, e2, e3)         -> PointsTo (map_e e1, map_e e2, map_e e3)
        | MetaData (e1, e2)             -> MetaData (map_e e1, map_e e2)
        | Emp                           -> Emp
        | Pred (s, le)                  -> Pred (s, List.map map_e le)
        | EmptyFields (o, ls)           -> EmptyFields (map_e o, map_e ls)
        | Pure form                     -> Pure (map_p form)
        | Types lt                      -> Types (List.map (fun (exp, typ) -> (map_e exp, typ)) lt) in
      f_a_after a''
    )


let rec fold 
  (feo      : (Expr.t -> 'a) option) 
  (fpo      : (Formula.t -> 'a) option)
  (f_ac     : t -> 'b -> 'b -> 'a list -> 'a)
  (f_state  : (t -> 'b -> 'b) option) 
  (state    : 'b)
  (asrt     : t) : 'a =
  
  let new_state = (Option.default (fun a x -> x) f_state) asrt state in
  let fold_a    = fold feo fpo f_ac f_state new_state in
  let f_ac      = f_ac asrt new_state state in
  let fes les   = Option.map_default (fun fe -> List.map fe les) [] feo in
  let fp form   = Option.map_default (fun fp -> [ fp form ]) [] fpo in 

  (* Not convinced these are correct *)
  match asrt with
  | Emp                      -> f_ac []
  | EmptyFields (le1, le2)   -> f_ac (fes [ le1; le2 ])
  | PointsTo (le1, le2, le3) -> f_ac (fes [ le1; le2; le3 ])
  | MetaData (le1, le2)      -> f_ac (fes [ le1; le2 ])
  | Pred (_, les)            -> f_ac (fes les)
  | Star (a1, a2)            -> f_ac [ (fold_a a1); (fold_a a2) ]
  | Pure form                -> f_ac (fp form)
  | Types vts -> 
    let les, _ = List.split vts in 
    f_ac (fes les) 


(* Returns all the non-list listerals that occur in --a-- *)
let non_list_lits (a : t) : Literal.t list =  
  let f_ac a _ _ ac = List.concat ac in
  let fe = Expr.non_list_lits in 
  let fp = Formula.fold (Some fe) f_ac None None in 
  fold (Some fe) (Some fp) f_ac None None a


(* Get all the logical expressions of --a-- of the form (Lit (LList lst)) and (EList lst)  *)
let lists (a : t) : Expr.t list =
  let f_ac a _ _ ac = List.concat ac in 
  let fe = Expr.lists in 
  let fp = Formula.fold (Some fe) f_ac None None in 
  fold (Some fe) (Some fp) f_ac None None a


(* Get all the logical expressions of --a-- that denote a list 
   and are not logical variables *)
let list_lexprs (a : t) : Expr.t list =

  let fe_ac le _ _ ac =
    match le with
    | Expr.Lit (LList _) | Expr.EList _   | Expr.BinOp (_, LstCons, _)
    | Expr.BinOp (_, LstCat, _) | Expr.UnOp (Car, _) | Expr.UnOp (Cdr, _)
    | Expr.UnOp (LstLen, _) -> le :: (List.concat ac)
    | _ -> List.concat ac in

  let fe = Expr.fold fe_ac None None in
  let f_ac a _ _ ac = List.concat ac in
  let fp = Formula.fold (Some fe) f_ac None None in 
  fold (Some fe) (Some fp) f_ac None None a

(* Get all the literal numbers and string occurring in --a-- *)
let strings_and_numbers (a : t) : (string list) * (float list) =
  let lits    = non_list_lits a in
  List.fold_left (fun (strings, numbers) (lit : Literal.t) -> 
    match lit with 
    | Num n    -> (strings, n :: numbers)
    | String s -> (s :: strings, numbers)
    | _        ->  (strings, numbers)
  ) ([], []) lits

(* Get all the logical variables in --a-- *)
let lvars (a : t) : SS.t =
  let fe_ac (le : Expr.t) _ _ (ac : string list list) : string list = 
    match le with
      | Expr.LVar x -> [ x ]
      | _      -> List.concat ac in 
  let fe   = Expr.fold fe_ac None None in 
  let fp f = SS.elements (Formula.lvars f) in  
  let f_ac a _ _ ac = List.concat ac in
  SS.of_list (fold (Some fe) (Some fp) f_ac None None a)

(* Get all the program variables in --a-- *)
let pvars (a : t) : SS.t =
  let fe_ac le _ _ ac = match le with
    | Expr.PVar x -> [ x ]
    | _      -> List.concat ac in 
  let fe = Expr.fold fe_ac None None in 
  let f_ac a _ _ ac = List.concat ac in
  let fp = Formula.fold (Some fe) f_ac None None in 
  SS.of_list (fold (Some fe) (Some fp) f_ac None None a)

(* Get all the abstract locations in --a-- *)
let rec alocs (a : t) : SS.t =
  let fe_ac le _ _ ac =
    match le with
    | Expr.ALoc l -> l :: (List.concat ac)
    | _ -> List.concat ac in
  let fe = Expr.fold fe_ac None None in 
  let f_ac a _ _ ac = List.concat ac in
  let fp = Formula.fold (Some fe) f_ac None None in 
  SS.of_list (fold (Some fe) (Some fp) f_ac None None a)

(* Get all the concrete locations in [a] *)
let rec clocs (a : t) : SS.t =
  let fe_ac le _ _ ac =
    match le with
    | Expr.Lit (Loc l) -> l :: (List.concat ac)
    | _ -> List.concat ac in
  let fe = Expr.fold fe_ac None None in 
  let f_ac a _ _ ac = List.concat ac in
  let fp = Formula.fold (Some fe) f_ac None None in 
  SS.of_list (fold (Some fe) (Some fp) f_ac None None a)

let base_elements (a : t) : Expr.Set.t = 
  let fe = Expr.base_elements in 
  let f_ac a _ _ ac = List.concat ac in
  let fp = Formula.fold (Some fe) f_ac None None in 
    Expr.Set.of_list (fold (Some fe) (Some fp) f_ac None None a)

(* Get all the variables in [a] *)
let vars (a : t) : SS.t =
  let vars = [alocs a; clocs a; lvars a; pvars a] in
  List.fold_left SS.union SS.empty vars


(* Get all the types in --a-- *)
let rec types (a : t) : (Expr.t * Type.t) list =
  let f_ac a _ _ ac =  
    match a with 
      | Types vts  -> vts @ (List.concat ac)
      | _          -> (List.concat ac) in 
  fold None None f_ac None None a

(* Returns a list with the names of the predicates that occur in --a-- *)
let pred_names (a : t) : string list =
  let f_ac a _ _ ac =
    (match a with
    | Pred (s, _) -> s :: (List.concat ac)
    | _            -> List.concat ac) in
  fold None None f_ac None None a

(* Returns a list with the pure assertions that occur in --a-- *)
let pure_asrts (a : t) : Formula.t list =
  let f_ac a _ _ ac =
    (match a with
    | Pure form    -> form :: (List.concat ac)
    | _            -> List.concat ac) in
  fold None None f_ac None None a


(* Returns a list with the pure assertions that occur in --a-- *)
let simple_asrts (a : t) : t list =
  let f_ac a _ _ ac =
    (match a with
    | Star (a1, a2)  -> List.concat ac
    | Emp            -> [ ]
    | a              -> [ a ]) in 
  fold None None f_ac None None a


(* Check if --a-- is a pure assertion *)
let is_pure_asrt (a : t) : bool =
  let f_ac a _ _ (ac : bool list) : bool =
    (match a with
    | Pred _ | PointsTo _ | Emp | EmptyFields _ | MetaData _ -> false
    | _  -> List.for_all (fun b -> b) ac) in
  let aux = fold None None f_ac None None in
  let ret = aux a in   
  ret

(* Check if --a-- is a pure assertion & non-recursive assertion. 
   It assumes that only pure assertions are universally quantified *)
let is_pure_non_rec_asrt (a : t) : bool =
  match a with
  | Pure _ | Types _ | Emp -> true
  | _      -> false


(* Eliminate LStar and LTypes assertions. 
   LTypes disappears. LStar is replaced by LAnd. 
   This function expects its argument to be a PURE assertion. *)
let make_pure (a : t) : Formula.t =
  let s_asrts = simple_asrts a in 
  let all_pure = List.for_all is_pure_non_rec_asrt s_asrts in 
  if all_pure then (
    let fs = List.map (fun a -> match a with | Pure f -> f | _ -> raise (Failure "DEATH. make_pure")) s_asrts in 
    Formula.conjunct fs 
  ) else raise (Failure "DEATH. make_pure")


let collect_types (a : t) : ((Expr.t * Type.t) list) = 
  let f_ac a _ _ ac = 
    (match a with 
      | Types vts -> vts @ (List.concat ac)
      | _         -> List.concat ac) in  
  fold None None f_ac None None a


(** JSIL logic assertions *)
let rec str (a : t) : string =
  let sle = Expr.str in
  match a with
  (* a1 * a2 *)
  | Star (a1, a2) -> Printf.sprintf "%s * %s" (str a1) (str a2)
  (* (e1, e2) -> e3 *)
  | PointsTo (e1, e2, e3) -> Printf.sprintf "((%s, %s) -> %s)" (sle e1) (sle e2) (sle e3)
  (* emp *)
  | Emp -> "emp"
  (* x(y1, ..., yn) *)
  | Pred (name, params) -> 
    Printf.sprintf "%s(%s)" name (String.concat ", " (List.map sle params))
  (* types(e1:t1, ..., en:tn) *)
  | Types type_list ->
      Printf.sprintf 
        "types(%s)"
        (String.concat ", " (List.map (fun (e, t) -> Printf.sprintf "%s : %s" (sle e) (Type.str t)) type_list))
  | EmptyFields (obj, domain) -> Printf.sprintf "empty_fields(%s : %s)" (sle obj) (sle domain)
  (* MetaData (e1, e2) *)
  | MetaData (e1, e2) -> Printf.sprintf "MetaData (%s, %s)" (sle e1) (sle e2)
  (* Pure *)
  | Pure f -> Formula.str f 

(** JSIL logic assertions *)
let rec full_str (a : t) : string =
  let f = full_str in 
  let sle = Expr.full_str in
  match a with
  (* a1 * a2 *)
  | Star (a1, a2) -> Printf.sprintf "%s * %s" (f a1) (f a2)
  (* (e1, e2) -> e3 *)
  | PointsTo (e1, e2, e3) -> Printf.sprintf "((%s, %s) -> %s)" (sle e1) (sle e2) (sle e3)
  (* emp *)
  | Emp -> "emp"
  (* x(y1, ..., yn) *)
  | Pred (name, params) -> Printf.sprintf "%s(%s)" name (String.concat ", " (List.map sle params))
  (* types(e1:t1, ..., en:tn) *)
  | Types type_list ->
      Printf.sprintf 
        "types(%s)"
        (String.concat ", " (List.map (fun (e, t) -> Printf.sprintf "%s : %s" (sle e) (Type.str t)) type_list))
  | EmptyFields (obj, domain) -> Printf.sprintf "empty_fields(%s : %s)" (sle obj) (sle domain)
  (* MetaData (e1, e2) *)
  | MetaData (e1, e2) -> Printf.sprintf "MetaData (%s, %s)" (sle e1) (sle e2)
  (* Pure *)
  | Pure f -> Formula.full_str f 

let str_of_assertion_list (a_list : t list) : string =
  String.concat "\t" (List.map str a_list)


let star (asses : t list) : t =
  List.fold_left
    (fun ac a ->
      if (not (a = Emp))
        then (if (ac = Emp) then a else Star (ac, a))
        else ac)
     Emp
    asses


let subst_clocs (subst : string -> Expr.t) (a : t) : t = 
  map None None (Some (Expr.subst_clocs subst)) (Some (Formula.subst_clocs subst)) a



let substitution (subst : SSubst.t) (partial : bool) (a : t) : t = 
  map None None (Some (SSubst.subst_in_expr subst partial)) (Some (Formula.substitution subst partial)) a


let filter_map_inplace f subst = Hashtbl.filter_map_inplace f subst 


let lift_logic_expr (e : Expr.t) : (t * t) option = 
  Option.map (fun (f, nf) -> Pure f, Pure nf) (Formula.lift_logic_expr e) 


