defmodule EmberLine.Modeling do
  @moduledoc """
  Modeling: the event-sourced Project and Slice streams. Commands go through
  `EmberLine.CommandedApp`; this Ash domain holds the read models that
  projections write.
  """
  use Ash.Domain, otp_app: :ember_line

  resources do
    resource EmberLine.Modeling.Projections.ProjectList
  end
end
