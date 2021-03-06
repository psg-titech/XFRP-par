open Syntax

exception Unreachable of string

module IntSet = Set.Make (Int)

let print_intset st =
  print_char '{' ;
  IntSet.iter (fun i -> print_int i ; print_char ',') st ;
  print_char '}'

type node_t =
    {
        name : string;
        t : Type.t;
        number : int;
        default : Syntax.const option;
    }

type program =
  { id: Syntax.moduleid ;
    (* The list of identifier of input nodes. *)
    input: Syntax.id list ;
    output: Syntax.id list ; (* list of identifier of output node *)
    node: Syntax.id list ; (* list of identifier of nodes. It includes input, output, and internal nodes. Note that gnode is not contained *)
    gnode: Syntax.id list ; (* list of gpu node *)

    (* A dictionary which maps from the node symbol(string) to node id(int). *)
    id_table: (string, int) Hashtbl.t ;

    (* A dictionary which contains the information of Node/GNode.
     * The information contains name, type of node.
     * Also, the table contains the number of node and default value when the node is array or gnode.
     * When the node is single node, the number of node is setted to 1. *)
    info_table : (int,node_t) Hashtbl.t;

    single_nodes : IntSet.t;
    node_arrays : IntSet.t;

    (* A dictionary that save the type of function *)
    func_table : (string, Type.t) Hashtbl.t;
  }

let default_functions = [
  ("pow", Type.TFloat);
]

(* Node/Gnode(string)からID(int)への辞書を構築する関数 *)
let construct_id_table (nodes : Syntax.id list) (gnodes : Syntax.id list) :
    (string, int) Hashtbl.t =
  let table = Hashtbl.create (List.length nodes + List.length gnodes) in
  List.iteri (fun i n -> Hashtbl.add table n i) (nodes @ gnodes) ;
  table

(* 各ノード(ID)とそのノードの情報のテーブル(info_table)を構築する関数 *)
let construct_nodeinfo_table (ast : Syntax.ast)
                             (id_table : (string,int) Hashtbl.t)
                             : (int,node_t) Hashtbl.t = 
    let table = Hashtbl.create 128 in

    (* Internal/Output Nodeをテーブルに追加 *)
    List.iter
        (function
            | Node ((name,t),_,_) ->
                let id = Hashtbl.find id_table name in
                Hashtbl.add table id { name; t; number=1; default=None; }
            | NodeA ((name,t),number,_,c,_) -> 
                let id = Hashtbl.find id_table name in
                Hashtbl.add table id { name; t; number; default=Some(c); }
            | GNode ((name,t), number, _, c, _) -> 
                let id = Hashtbl.find id_table name in
                Hashtbl.add table id { name; t; number; default=Some(c); }
            | Func _ -> ())
        ast.definitions;

    (* Input Nodeがまだテーブルに含まれていないので追加 *)
    List.iter
        (function
            | Single (name,t) ->
                let id = Hashtbl.find id_table name in
                Hashtbl.add table id { name; t; number=1; default=None; }
            | Array ((name,t),number, c) -> 
                let id = Hashtbl.find id_table name in
                Hashtbl.add table id { name; t; number; default=c; })
        ast.in_nodes;
    table

(* This function returns the dictionary whose key is the name of function and the value of dictionary is the return type of function. *)
let construct_function_table (ast : Syntax.ast) : (string,Type.t) Hashtbl.t =
  let tbl = Hashtbl.create 10 in
  List.iter
    (function
      | Func ((i,t), _ , _) -> Hashtbl.add tbl i t
      | _ -> ()
    )
    ast.definitions;
  List.iter (fun (sym, t) -> Hashtbl.add tbl sym t) default_functions;
  tbl


(* ASTから依存関係を抽出 *)
let ast_to_program : Syntax.ast -> program = fun ast ->
  let input = List.map Syntax.name_of_cpunode ast.in_nodes in
  let output = List.map Syntax.name_of_cpunode ast.out_nodes in
  (* nodeのリストを構築 *)
  let node =
    let internal_and_output =
      List.filter_map
        (function
          | Node ((i, _), _, _) ->
              Some i
          | NodeA ((i, _), _, _, _, _) ->
              Some i
          | _ ->
              None)
        ast.definitions
    in
    input @ internal_and_output
  in
  (* gpu nodeのリストを構築 *)
  let gnode =
    List.filter_map
      (function GNode ((i, _), _, _, _, _) -> Some i | _ -> None)
      ast.definitions
  in
  let id_table = construct_id_table node gnode in
  let info_table = construct_nodeinfo_table ast id_table in
  let single_nodes = 
    let single_list = List.filter_map
      (fun symbol ->
        let id = Hashtbl.find id_table symbol in
        let info = Hashtbl.find info_table id in
        if info.number = 1  then Some(id)
                            else None)
      node
    in
    IntSet.of_list single_list
  in
  let node_arrays = 
    let arrays_list = List.filter_map
      (fun symbol -> 
        let id = Hashtbl.find id_table symbol in
        let info = Hashtbl.find info_table id in
        if info.number > 1 then Some(id)
        else None)
      node
    in
    IntSet.of_list arrays_list
  in
  let func_table = construct_function_table ast in
  {id= ast.module_id; input; output; node; gnode; id_table; info_table; single_nodes; node_arrays; func_table;}

let print_program prog : unit =
  Printf.printf "Module : %s\n" prog.id ;
  Printf.printf "Input : %s\n" (String.concat ", " prog.input) ;
  Printf.printf "Output: %s\n" (String.concat ", " prog.output) ;
  Printf.printf "Node : %s\n" (String.concat ", " prog.node) ;
  Printf.printf "GNode : %s\n" (String.concat ", " prog.gnode)

(* プログラム中のノードの数. Gnodeは展開前の1つで計算する *)
let node_num prog : int = Hashtbl.length prog.id_table

(* デバッグ用関数 *)
let show_id_table prg = 
  Printf.eprintf "========== ID Table ==========\n";
  Hashtbl.iter (fun k v -> Printf.eprintf "%s : %d\n" k v) prg.id_table;
  Printf.eprintf "==============================\n";
