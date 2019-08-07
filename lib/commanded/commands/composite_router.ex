defmodule Commanded.Commands.CompositeRouter do
  @moduledoc """
  Composite router allows you to combine multiple router modules into a single
  router able to dispatch any registered command using its corresponding router.

  ## Example

      defmodule ExampleCompositeRouter do
        use Commanded.Commands.CompositeRouter

        router BankAccountRouter
        router MoneyTransferRouter
      end

      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      :ok = ExampleCompositeRouter.dispatch(command)
  """

  defmacro __using__(opts) do
    quote do
      require Logger

      import unquote(__MODULE__)

      @registered_commands %{}
      @application Keyword.get(unquote(opts), :application)

      @before_compile unquote(__MODULE__)
    end
  end

  defmacro router(router_module) do
    quote location: :keep do
      for command <- unquote(router_module).__registered_commands__() do
        case Map.get(@registered_commands, command) do
          nil ->
            @registered_commands Map.put(@registered_commands, command, unquote(router_module))

          existing_router ->
            raise "duplicate registration for #{inspect(command)} command, registered in both #{
                    inspect(existing_router)
                  } and #{inspect(unquote(router_module))}"
        end
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote generated: true do
      @doc false
      def __registered_commands__ do
        Enum.map(@registered_commands, fn {command, _router} -> command end)
      end

      @doc false
      def dispatch(command, opts \\ [])

      Enum.map(@registered_commands, fn {command_module, router} ->
        Module.eval_quoted(
          __MODULE__,
          quote do
            @doc false
            def dispatch(%unquote(command_module){} = command, :infinity) do
              unquote(router).dispatch(command, application: @application, timeout: :infinity)
            end

            @doc false
            def dispatch(%unquote(command_module){} = command, timeout)
                when is_integer(timeout) do
              unquote(router).dispatch(command, application: @application, timeout: timeout)
            end

            @doc false
            def dispatch(%unquote(command_module){} = command, opts) do
              unquote(router).dispatch(command, Keyword.put_new(opts, :application, @application))
            end
          end
        )
      end)

      @doc false
      def dispatch(command, _opts) do
        Logger.error(fn ->
          "attempted to dispatch an unregistered command: " <> inspect(command)
        end)

        {:error, :unregistered_command}
      end
    end
  end
end
