# Script for populating the database with sample data.
#
# You can run this script with:
#   mix run priv/repo/seeds.exs
#
# Or in production:
#   MIX_ENV=prod mix run priv/repo/seeds.exs
#
# To reset and re-seed:
#   mix ecto.reset && mix run priv/repo/seeds.exs

alias Backend.Repo
alias Backend.Notes.Note

require Logger

Logger.info("Starting database seed...")

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Demo user IDs (simulating OAuth provider UIDs)
demo_users = [
  %{id: "demo:user1", name: "Alice Demo"},
  %{id: "demo:user2", name: "Bob Demo"},
  %{id: "demo:user3", name: "Charlie Demo"}
]

# Number of notes per user
notes_per_user = 10

# Sample content for notes
sample_contents = [
  "This is a sample note with some content. You can edit or delete it.",
  "Remember to buy groceries: milk, eggs, bread, and cheese.",
  "Meeting notes from today's standup:\n- Discussed sprint progress\n- Reviewed blockers\n- Planned next steps",
  "Ideas for the weekend:\n1. Go hiking\n2. Try a new restaurant\n3. Read a book",
  "Code review feedback:\n- Good test coverage\n- Consider extracting helper function\n- Nice use of pattern matching",
  "Project milestones:\n[ ] Phase 1 - MVP\n[ ] Phase 2 - Beta launch\n[ ] Phase 3 - GA release",
  "Quick note to self: Follow up with the team about the deployment schedule.",
  "Book recommendations:\n- Clean Code by Robert Martin\n- The Pragmatic Programmer\n- Designing Data-Intensive Applications",
  "Learning goals for this quarter:\n- Master Elixir/Phoenix\n- Learn more about AWS\n- Improve system design skills",
  "Recipe: Simple pasta\n1. Boil water\n2. Add pasta\n3. Cook for 8-10 minutes\n4. Add sauce\n5. Enjoy!"
]

# -----------------------------------------------------------------------------
# Seed Notes
# -----------------------------------------------------------------------------

Logger.info("Seeding notes for #{length(demo_users)} demo users...")

for user <- demo_users do
  Logger.info("Creating notes for #{user.name}...")

  for i <- 1..notes_per_user do
    content = Enum.at(sample_contents, rem(i - 1, length(sample_contents)))

    attrs = %{
      title: "#{user.name}'s Note ##{i}",
      content: content,
      user_id: user.id,
      archived: i > notes_per_user - 2  # Last 2 notes are archived
    }

    case Repo.insert(%Note{} |> Note.create_changeset(attrs, user.id)) do
      {:ok, note} ->
        Logger.debug("Created note: #{note.title}")

      {:error, changeset} ->
        Logger.error("Failed to create note: #{inspect(changeset.errors)}")
    end
  end
end

Logger.info("Database seed complete!")
Logger.info("Created #{length(demo_users) * notes_per_user} notes")
