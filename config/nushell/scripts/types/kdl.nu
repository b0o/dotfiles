# Convert a Nu data structure to KDL
# The root must be a list of nodes, not a single node
# Depends on https://github.com/joshprk/jsonkdl
export def "to kdl" [
  --version (-v): string # "1" or "2" for kdl version
]: list<record> -> string {
  if ($version | is-not-empty) and ($version not-in ["1" "2"]) {
    error make -u {msg: $"Error: Invalid KDL version: ($version)"}
  }

  # TODO: Pass to jsonkdl stdin when https://github.com/joshprk/jsonkdl/issues/10 is fixed
  let tmp = mktemp --dry -t --suffix .json
  $in | save $tmp
  let args = [
    ...(if ($version | is-not-empty) { [$"-($version)"] })
  ]
  let res = ^jsonkdl ...$args $tmp | complete
  rm -f $tmp
  if $res.exit_code != 0 {
    error make -u {msg: $"jsonkdl failed: ($res.stderr)"}
  }
  $res.stdout | str trim
}

def eval [val] {
  let type = $val | describe --detailed | get type
  if $type == "closure" {
    eval (do $val)
  } else if $type == "list" {
    $val | each {|item| eval $item } | compact
  } else if $type == "record" {
    $val | items { |k, v| { $k: (eval $v) } } | into record | compact
  } else {
    $val
  }
}

# Build a KDL node as a record
export def node [
  name: string
  ...children: oneof<record,closure> # Child nodes or closures returning child nodes
  --props: oneof<record,closure>  # Props to become `node name=value` pairs on the node
  --args: oneof<list,closure> # Arguments to become `node arg` key on the node
]: nothing -> record {
  mut result = { name: $name }
  if ($args | is-not-empty) {
    $result = ($result | insert arguments (eval $args))
  }
  if ($props | is-not-empty) {
    $result = ($result | insert properties (eval $props))
  }
  if ($children | is-not-empty) {
    $result = ($result | insert children (eval $children))
  }
  $result
}

# Build a KDL document tree
export def root [
  ...nodes: oneof<record,closure> # KDL document nodes
] {
  eval $nodes
}
