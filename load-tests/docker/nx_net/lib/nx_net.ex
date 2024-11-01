defmodule NxNet do
  @moduledoc """
  NxNet keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  def load_model do
    {:ok, _resnet} = Bumblebee.load_model({:hf, "microsoft/resnet-50"})
    {:ok, _featurizer} = Bumblebee.load_featurizer({:hf, "microsoft/resnet-50"})

    :ok
  end
end
