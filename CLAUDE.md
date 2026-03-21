## ClaudeOnRails Configuration

You are working on Hindsite, a Rails application.

### Required Reading

Before writing any code, review:

- **@STYLE.md** - DHH/Fizzy patterns and code style (MUST follow)

### Key Style Points

1. **Visibility modifiers**: No blank line after `private`, indent methods under it
2. **Conditionals**: Prefer expanded `if/else` over guard clauses, BUT guard clauses ARE acceptable when:
   - The return is right at the beginning of the method
   - The main method body is non-trivial (several lines of code)
3. **Predicate methods**: Use `&&` chains, NOT multiple `return false unless` guard clauses
4. **Methods ordering**: Class methods, public methods (initialize first), private methods in invocation order
5. **Model concerns**: `app/models/model_name/concern.rb` for model-specific, `app/models/concerns/` for shared
6. **Controller concerns**: Use `*Scoped` suffix for scoping concerns (e.g., `FilterScoped`)
7. **CRUD resources**: Every action maps to CRUD - "closing" = POST to /thing/closure
8. **No comments**: Code should be self-documenting
9. **JavaScript**: Double quotes, `#` prefix for private methods, static declarations at top

### Guard Clause Guidelines

Guard clauses are acceptable when used at the beginning of a method with a non-trivial body:

```ruby
# Good - guard clause at start, non-trivial body follows
def after_recorded_as_commit(recording)
  return if recording.parent.was_created?

  if recording.was_created?
    broadcast_new_column(recording)
  else
    broadcast_column_change(recording)
  end
end

# Bad - guard clause mid-method or with trivial body
def todos_for_new_group
  ids = params.require(:todolist)[:todo_ids]
  return [] unless ids  # Bad: not at beginning
  @bucket.recordings.todos.find(ids.split(","))
end

# Good - expanded conditional for simple methods
def todos_for_new_group
  if ids = params.require(:todolist)[:todo_ids]
    @bucket.recordings.todos.find(ids.split(","))
  else
    []
  end
end
```

### Predicate Method Pattern

```ruby
# Bad - multiple guard clause returns
def alertable?
  return false unless condition1
  return false unless condition2
  true
end

# Good - && chain
def alertable?
  condition1 && condition2
end

# Good - single guard for type check, then && chain
def alertable?
  step_input = workflow_step_input
  return false unless step_input.is_a?(WorkflowStepInput)

  step_input.notify_operational_lead? &&
    saved_change_to_input? &&
    answered?
end
```

### Reference Implementation

The Fizzy codebase at `~/Code/fizzy` serves as the reference for DHH's style.
