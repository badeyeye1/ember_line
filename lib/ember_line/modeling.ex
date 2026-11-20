defmodule EmberLine.Modeling do
  @moduledoc """
  Modeling: the event-sourced Project and Slice streams. Commands go through
  `EmberLine.CommandedApp`; this Ash domain holds the read models that
  projections write.
  """
  use Ash.Domain, otp_app: :ember_line

  resources do
    resource EmberLine.Modeling.Projections.ProjectList
    resource EmberLine.Modeling.Projections.PrototypeScreens
    resource EmberLine.Modeling.PrototypeFile
    resource EmberLine.Modeling.PrototypePage
    resource EmberLine.Modeling.DerivationRun
    resource EmberLine.Modeling.Derivation
    resource EmberLine.Modeling.Projections.SlicesToCreate
    resource EmberLine.Modeling.Projections.AddedSlices
  end
end
