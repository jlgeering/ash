defmodule Ash.Test.Actions.BulkUpdateTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Ash.Test.Domain, as: Domain

  defmodule AddAfterToTitle do
    use Ash.Resource.Change

    @impl true
    def change(changeset, _, _) do
      changeset
    end

    @impl true
    def batch_change(changesets, _opts, _context) do
      changesets
    end

    @impl true
    def after_batch(results, _, _) do
      Stream.map(results, fn {_changeset, result} ->
        {:ok, %{result | title: result.title <> "_after"}}
      end)
    end
  end

  defmodule AddBeforeToTitle do
    use Ash.Resource.Change

    @impl true
    def change(changeset, _, %{bulk?: true}) do
      changeset
    end

    @impl true
    def before_batch(changesets, _, _) do
      Stream.map(changesets, fn changeset ->
        title = Ash.Changeset.get_attribute(changeset, :title)
        Ash.Changeset.force_change_attribute(changeset, :title, "before_" <> title)
      end)
    end
  end

  defmodule RecordBatchSizes do
    use Ash.Resource.Change

    @impl true
    def batch_change(changesets, _, _) do
      batch_size = length(changesets)

      Stream.map(changesets, fn changeset ->
        Ash.Changeset.force_change_attribute(changeset, :change_batch_size, batch_size)
      end)
    end

    @impl true
    def before_batch(changesets, _, _) do
      batch_size = length(changesets)

      Stream.map(changesets, fn changeset ->
        Ash.Changeset.force_change_attribute(changeset, :before_batch_size, batch_size)
      end)
    end

    @impl true
    def after_batch(results, _, _) do
      batch_size = length(results)

      Stream.map(results, fn {_, result} ->
        {:ok, %{result | after_batch_size: batch_size}}
      end)
    end
  end

  defmodule Post do
    @moduledoc false
    use Ash.Resource,
      domain: Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private? true
    end

    actions do
      default_accept :*
      defaults [:read, :destroy, create: :*, update: :*]

      update :update_with_change do
        require_atomic? false

        change fn changeset, _ ->
          title = Ash.Changeset.get_attribute(changeset, :title)
          Ash.Changeset.force_change_attribute(changeset, :title, title <> "_stuff")
        end
      end

      update :update_with_argument do
        require_atomic? false

        argument :a_title, :string do
          allow_nil? false
        end

        change set_attribute(:title2, arg(:a_title))
      end

      update :update_with_after_action do
        require_atomic? false

        change after_action(fn _changeset, result, _context ->
                 {:ok, %{result | title: result.title <> "_stuff"}}
               end)
      end

      update :update_with_after_batch do
        require_atomic? false
        change AddAfterToTitle
        change AddBeforeToTitle
      end

      update :update_with_batch_sizes do
        require_atomic? false
        change RecordBatchSizes
      end

      update :update_with_after_transaction do
        require_atomic? false

        change after_transaction(fn _changeset, {:ok, result}, _context ->
                 {:ok, %{result | title: result.title <> "_stuff"}}
               end)
      end

      update :update_with_policy do
        require_atomic? false
        argument :authorize?, :boolean, allow_nil?: false

        change set_context(%{authorize?: arg(:authorize?)})
      end
    end

    identities do
      identity :unique_title, :title do
        pre_check_with Ash.Test.Actions.BulkUpdateTest.Domain
      end
    end

    calculations do
      calculate :hidden_calc, :string, expr("something") do
        public?(true)
      end
    end

    field_policies do
      field_policy [:hidden_calc, :hidden_attribute] do
        forbid_if always()
      end

      field_policy :* do
        authorize_if always()
      end
    end

    policies do
      policy action(:update_with_policy) do
        authorize_if context_equals(:authorize?, true)
      end

      policy always() do
        authorize_if always()
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :title, :string, allow_nil?: false, public?: true
      attribute :title2, :string, public?: true
      attribute :title3, :string, public?: true
      attribute :hidden_attribute, :string, public?: true

      attribute :before_batch_size, :integer
      attribute :after_batch_size, :integer
      attribute :change_batch_size, :integer

      timestamps()
    end
  end

  test "returns updated records" do
    assert %Ash.BulkResult{records: [%{title2: "updated value"}, %{title2: "updated value"}]} =
             Ash.bulk_create!([%{title: "title1"}, %{title: "title2"}], Post, :create,
               return_stream?: true,
               return_records?: true,
               authorize?: false
             )
             |> Stream.map(fn {:ok, result} ->
               result
             end)
             |> Ash.bulk_update!(:update, %{title2: "updated value"},
               resource: Post,
               strategy: :atomic_batches,
               return_records?: true,
               return_errors?: true,
               authorize?: false
             )
  end

  test "runs changes" do
    assert %Ash.BulkResult{
             records: [
               %{title: "title1_stuff", title2: "updated value"},
               %{title: "title2_stuff", title2: "updated value"}
             ]
           } =
             Ash.bulk_create!([%{title: "title1"}, %{title: "title2"}], Post, :create,
               return_stream?: true,
               return_records?: true,
               authorize?: false
             )
             |> Stream.map(fn {:ok, result} ->
               result
             end)
             |> Ash.bulk_update!(:update_with_change, %{title2: "updated value"},
               resource: Post,
               strategy: :stream,
               return_records?: true,
               return_errors?: true,
               authorize?: false
             )
             |> Map.update!(:records, fn records ->
               Enum.sort_by(records, & &1.title)
             end)
  end

  test "accepts arguments" do
    assert %Ash.BulkResult{
             records: [
               %{title: "title1", title2: "updated value"},
               %{title: "title2", title2: "updated value"}
             ]
           } =
             Ash.bulk_create!([%{title: "title1"}, %{title: "title2"}], Post, :create,
               return_stream?: true,
               return_records?: true,
               authorize?: false
             )
             |> Stream.map(fn {:ok, result} ->
               result
             end)
             |> Ash.bulk_update!(:update_with_argument, %{a_title: "updated value"},
               resource: Post,
               return_records?: true,
               return_errors?: true,
               authorize?: false
             )
             |> Map.update!(:records, fn records ->
               Enum.sort_by(records, & &1.title)
             end)
  end

  test "runs after batch hooks" do
    assert %Ash.BulkResult{
             records: [
               %{title: "before_title1_after", title2: "updated value"},
               %{title: "before_title2_after", title2: "updated value"}
             ]
           } =
             Ash.bulk_create!([%{title: "title1"}, %{title: "title2"}], Post, :create,
               return_stream?: true,
               return_records?: true,
               authorize?: false
             )
             |> Stream.map(fn {:ok, result} ->
               result
             end)
             |> Ash.bulk_update!(:update_with_after_batch, %{title2: "updated value"},
               resource: Post,
               strategy: :stream,
               return_records?: true,
               return_errors?: true,
               authorize?: false
             )
             |> Map.update!(:records, fn records ->
               Enum.sort_by(records, & &1.title)
             end)
  end

  test "runs changes in batches" do
    create_records = fn count ->
      Stream.iterate(1, &(&1 + 1))
      |> Stream.map(fn i -> %{title: "title#{i}"} end)
      |> Ash.bulk_create!(Post, :create, return_stream?: true, return_records?: true)
      |> Stream.map(fn {:ok, result} -> result end)
      |> Stream.take(count)
    end

    update_records = fn records, opts ->
      opts = [resource: Post, return_records?: true, strategy: :stream] ++ opts
      Ash.bulk_update!(records, :update_with_batch_sizes, %{}, opts)
    end

    batch_size_frequencies = fn %Ash.BulkResult{records: records} ->
      records
      |> Enum.map(&Map.take(&1, [:before_batch_size, :after_batch_size, :change_batch_size]))
      |> Enum.frequencies()
    end

    assert create_records.(101)
           |> update_records.([])
           |> batch_size_frequencies.() == %{
             %{change_batch_size: 100, before_batch_size: 100, after_batch_size: 100} => 100,
             %{change_batch_size: 1, before_batch_size: 1, after_batch_size: 1} => 1
           }

    assert create_records.(10)
           |> update_records.(batch_size: 3)
           |> batch_size_frequencies.() == %{
             %{change_batch_size: 3, before_batch_size: 3, after_batch_size: 3} => 9,
             %{change_batch_size: 1, before_batch_size: 1, after_batch_size: 1} => 1
           }
  end

  test "will return error count" do
    assert %Ash.BulkResult{
             error_count: 2
           } =
             Ash.bulk_create!([%{title: "title1"}, %{title: "title2"}], Post, :create,
               return_stream?: true,
               return_records?: true,
               authorize?: false
             )
             |> Stream.map(fn {:ok, result} ->
               result
             end)
             |> Ash.bulk_update(:update, %{title2: %{invalid: :value}},
               resource: Post,
               strategy: :stream,
               return_records?: true,
               authorize?: false
             )
  end

  test "will return errors on request" do
    assert %Ash.BulkResult{
             error_count: 1,
             errors: [%Ash.Error.Invalid{}]
           } =
             Ash.bulk_create!([%{title: "title1"}], Post, :create,
               return_stream?: true,
               return_records?: true,
               authorize?: false
             )
             |> Stream.map(fn {:ok, result} ->
               result
             end)
             |> Ash.bulk_update(:update, %{title2: %{invalid: :value}},
               strategy: :stream,
               resource: Post,
               return_errors?: true,
               authorize?: false
             )
  end

  test "runs after action hooks" do
    assert %Ash.BulkResult{
             records: [
               %{title: "title1_stuff", title2: "updated value"},
               %{title: "title2_stuff", title2: "updated value"}
             ]
           } =
             Ash.bulk_create!([%{title: "title1"}, %{title: "title2"}], Post, :create,
               return_stream?: true,
               return_records?: true,
               authorize?: false
             )
             |> Stream.map(fn {:ok, result} ->
               result
             end)
             |> Ash.bulk_update!(:update_with_after_action, %{title2: "updated value"},
               resource: Post,
               strategy: :stream,
               return_records?: true,
               return_errors?: true,
               authorize?: false
             )
             |> Map.update!(:records, fn records ->
               Enum.sort_by(records, & &1.title)
             end)
  end

  test "runs after transaction hooks" do
    assert %Ash.BulkResult{
             records: [
               %{title: "title1_stuff", title2: "updated value"},
               %{title: "title2_stuff", title2: "updated value"}
             ]
           } =
             Ash.bulk_create!([%{title: "title1"}, %{title: "title2"}], Post, :create,
               return_stream?: true,
               return_records?: true,
               authorize?: false
             )
             |> Stream.map(fn {:ok, result} ->
               result
             end)
             |> Ash.bulk_update!(:update_with_after_transaction, %{title2: "updated value"},
               resource: Post,
               strategy: :stream,
               return_records?: true,
               return_errors?: true,
               authorize?: false
             )
             |> Map.update!(:records, fn records ->
               Enum.sort_by(records, & &1.title)
             end)
  end

  describe "authorization" do
    test "policy success results in successes" do
      assert %Ash.BulkResult{records: [_, _], errors: []} =
               Ash.bulk_create!([%{title: "title1"}, %{title: "title2"}], Post, :create,
                 return_stream?: true,
                 return_records?: true,
                 authorize?: false
               )
               |> Stream.map(fn {:ok, result} ->
                 result
               end)
               |> Ash.bulk_update(
                 :update_with_policy,
                 %{title2: "updated value", authorize?: true},
                 authorize?: true,
                 resource: Post,
                 return_records?: true,
                 return_errors?: true
               )
    end

    test "field authorization is run" do
      assert %Ash.BulkResult{
               records: [
                 %{
                   hidden_attribute: %Ash.ForbiddenField{},
                   hidden_calc: %Ash.ForbiddenField{}
                 },
                 %{
                   hidden_attribute: %Ash.ForbiddenField{},
                   hidden_calc: %Ash.ForbiddenField{}
                 }
               ],
               errors: []
             } =
               Ash.bulk_create!([%{title: "title1"}, %{title: "title2"}], Post, :create,
                 return_stream?: true,
                 return_records?: true,
                 authorize?: false
               )
               |> Stream.map(fn {:ok, result} ->
                 result
               end)
               |> Ash.bulk_update(
                 :update_with_policy,
                 %{title2: "updated value", authorize?: true},
                 authorize?: true,
                 resource: Post,
                 return_records?: true,
                 return_errors?: true,
                 load: [:hidden_calc]
               )
    end

    test "policy failure results in failures" do
      assert %Ash.BulkResult{errors: [%Ash.Error.Forbidden{}], records: []} =
               Ash.bulk_create!([%{title: "title1"}, %{title: "title2"}], Post, :create,
                 return_stream?: true,
                 return_records?: true,
                 authorize?: false
               )
               |> Stream.map(fn {:ok, result} ->
                 result
               end)
               |> Ash.bulk_update(
                 :update_with_policy,
                 %{title2: "updated value", authorize?: false},
                 strategy: :atomic,
                 authorize?: true,
                 resource: Post,
                 return_records?: true,
                 return_errors?: true
               )

      assert %Ash.BulkResult{
               errors: [%Ash.Error.Forbidden{}, %Ash.Error.Forbidden{}],
               records: []
             } =
               Ash.bulk_create!([%{title: "title1"}, %{title: "title2"}], Post, :create,
                 return_stream?: true,
                 return_records?: true,
                 authorize?: false
               )
               |> Stream.map(fn {:ok, result} ->
                 result
               end)
               |> Ash.bulk_update(
                 :update_with_policy,
                 %{title2: "updated value", authorize?: false},
                 strategy: :stream,
                 authorize?: true,
                 resource: Post,
                 return_records?: true,
                 return_errors?: true
               )
    end
  end
end
