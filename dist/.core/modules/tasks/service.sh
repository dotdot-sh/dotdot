#!/usr/bin/env bash

dot::use framework.helpers.fs framework.helpers.template framework.helpers.text

TASK_TEMPLATE="$MODULES_DIR/tasks/skills/dot-create-task/task-template.md"
TASK_DRIVERS_DIR="$MODULES_DIR/tasks/drivers"
TASK_SETUP_SUFFIX="-setup"
TASK_PAGE_SIZE=25
TASK_ID_PATTERN='^#?[A-Za-z0-9][A-Za-z0-9._-]*$'
TASK_SERVICE_PATTERN='^[a-z0-9][a-z0-9-]*$'
TASK_SERVICE_KEY="TASKS_SERVICE"
TASK_GUIDANCE_PATTERN='^<!-- .* -->$'
TASK_SORT_COLUMNS=" created updated "
TASK_CREATED_COLUMN=3
TASK_UPDATED_COLUMN=4

core.modules.tasks.service::require_template() {
  [ -f "$TASK_TEMPLATE" ] || dot::abort "Template not found: $(dot::relative "$TASK_TEMPLATE")"
}

core.modules.tasks.service::statuses() {
  framework.helpers.template::options "$TASK_TEMPLATE" status
}

core.modules.tasks.service::default_status() {
  core.modules.tasks.service::statuses | head -n 1
}

core.modules.tasks.service::is_status() {
  core.modules.tasks.service::statuses | grep -xF -- "$1" >/dev/null
}

core.modules.tasks.service::sections() {
  framework.helpers.template::headings "$TASK_TEMPLATE"
}

core.modules.tasks.service::services() {
  local file
  for file in "$TASK_DRIVERS_DIR"/*.sh; do
    case "$file" in
      *"$TASK_SETUP_SUFFIX.sh") continue ;;
    esac
    [ -f "$file" ] && basename -- "$file" .sh
  done
  return 0
}

core.modules.tasks.service::service_description() {
  sed -n 's/^DESCRIPTION="\(.*\)"$/\1/p' "$TASK_DRIVERS_DIR/$1.sh" | head -n 1
}

core.modules.tasks.service::selected_service() {
  dot::optional_config "$TASK_SERVICE_KEY"
}

core.modules.tasks.service::select_service() {
  dot::save_config "$TASK_SERVICE_KEY" "$1"
}

core.modules.tasks.service::load_service() {
  local service="$1"
  [[ "$service" =~ $TASK_SERVICE_PATTERN ]] || dot::abort "Invalid task service: $service"
  [ -f "$TASK_DRIVERS_DIR/$service.sh" ] || dot::abort "Task service \"$service\" is not installed."
  dot::use "core.modules.tasks.drivers.$service"
  TASKS_SERVICE="$service"
}

core.modules.tasks.service::driver() {
  printf 'core.modules.tasks.drivers.%s::%s\n' "$TASKS_SERVICE" "$1"
}

core.modules.tasks.service::check_title() {
  [ -n "$1" ] || dot::abort "The title can't be empty."
  framework.helpers.text::is_one_line "$1" || dot::abort "The title must be one line."
}

core.modules.tasks.service::check_id() {
  [ -n "${1-}" ] || dot::abort "Missing the task id. Run bash dot tasks:list to see them."
  [[ "$1" =~ $TASK_ID_PATTERN ]] || dot::abort "Invalid task id: $1"
}

core.modules.tasks.service::set_section() {
  local sections_dir="$1" key="$2" value="$3"
  framework.helpers.template::has_key "$TASK_TEMPLATE" "$key" || return 1
  printf '%s' "$value" > "$sections_dir/$key"
}

core.modules.tasks.service::given_sections() {
  local sections_dir="$1" key
  while IFS= read -r key; do
    [ ! -e "$sections_dir/$key" ] || printf '%s\n' "$key"
  done < <(framework.helpers.template::keys "$TASK_TEMPLATE")
}

core.modules.tasks.service::read_body_file() {
  local source="$1" destination="$2" path
  if [ "$source" = "-" ]; then
    cat > "$destination"
    return
  fi
  path=$(framework.helpers.fs::within "$source" "$BASE") || dot::abort "--body-file must be inside the project: $source"
  [ -f "$path" ] || dot::abort "--body-file not found: $source"
  cat -- "$path" > "$destination"
}

core.modules.tasks.service::compose_body() {
  framework.helpers.template::compose "$TASK_TEMPLATE" "$1"
}

core.modules.tasks.service::apply_sections() {
  local body="$1" sections_dir="$2" key
  while IFS= read -r key; do
    framework.helpers.template::replace_section "$body" "$(framework.helpers.template::heading "$TASK_TEMPLATE" "$key")" "$sections_dir/$key"
  done < <(core.modules.tasks.service::given_sections "$sections_dir")
}

core.modules.tasks.service::add_guidance() {
  awk -v template="$TASK_TEMPLATE" -v empty="$TEMPLATE_EMPTY_SECTION" '
    BEGIN {
      while ((getline line < template) > 0) {
        if (line ~ /^## /) { heading = line; continue }
        if (heading == "" || line == "") continue
        if (heading in guidance) guidance[heading] = guidance[heading] " " line; else guidance[heading] = line
      }
      heading = ""
    }
    function flush() {
      sub(/\n+$/, "", body)
      if (heading == "") { if (body != "") { print body; print "" } }
      else if (body == empty && (heading in guidance)) { print heading; print "<!-- " guidance[heading] " -->"; print ""; print "" }
      else { print heading; print ""; print body; print "" }
      body = ""
    }
    /^## / { flush(); heading = $0; next }
    { if ($0 == "" && body == "") next; body = (body == "" ? $0 : body "\n" $0) }
    END { flush() }
  ' "$1" | framework.helpers.fs::replace "$1"
}

core.modules.tasks.service::strip_guidance() {
  awk -v empty="$TEMPLATE_EMPTY_SECTION" -v guidance="$TASK_GUIDANCE_PATTERN" '
    function flush() {
      sub(/\n+$/, "", body)
      if (heading != "") { print heading; print ""; print (body == "" ? empty : body); print "" }
      else if (body != "") { print body; print "" }
      body = ""
    }
    $0 ~ guidance { next }
    /^## / { flush(); heading = $0; next }
    {
      if ($0 == "" && body == "") next
      body = (body == "" ? $0 : body "\n" $0)
    }
    END { flush() }
  ' "$1" | awk 'NF || seen { print } { if (NF) seen = 1 }' | framework.helpers.fs::replace "$1"
  framework.helpers.template::trim_trailing_blank_lines "$1"
}

core.modules.tasks.service::is_blank() {
  ! grep -q '[^[:space:]]' "$1"
}

core.modules.tasks.service::is_sort_column() {
  [[ "$TASK_SORT_COLUMNS" == *" $1 "* ]]
}

core.modules.tasks.service::sort_rows() {
  local rows="$1" statuses="$2" sort="$3" order="$4" column="$TASK_CREATED_COLUMN" reverse=""
  [ "$sort" != updated ] || column="$TASK_UPDATED_COLUMN"
  [ "$order" != desc ] || reverse=r
  awk -F '\t' -v wanted="$statuses" 'wanted == "" || index(wanted, " " $2 " ")' "$rows" \
    | sort -t $'\t' -k "$column,$column$reverse" -k "1,1$reverse"
}
