defmodule Project2 do

    @process_registry_name :process_registry

      def main(args \\ []) do
        args |> parse_args
      end

      defp parse_args(args) do

        numNodes = Enum.at(args,0) |> String.trim
        topology = Enum.at(args,1) |> String.trim
        algorithm = Enum.at(args,2) |> String.trim
        numNodes = String.to_integer(numNodes)
        Registry.start_link(keys: :unique, name: :process_registry)
        parent = self()
        populate_processes(numNodes, topology, algorithm)

        node = :rand.uniform(numNodes)
        :timer.sleep(:timer.seconds(1))
        startTime =  :os.system_time(:millisecond)

        if(algorithm == "gossip") do
          pid = whereis(node)
          case pid do
            nil -> IO.puts "no pid exists"
            pid -> send pid, {:start, "Rumor1", 0, node, numNodes, parent}
          end
        else
          pid = whereis(node)
          case pid do
            nil -> IO.puts "no pid exists"
            pid -> send pid, {:start_push_sum, 0, 0, 0, node, parent}
          end
        end
          main_receive(numNodes, startTime,0)
    end

    def main_receive(numNodes, startTime, count) do
      receive do
          {:done} ->count = count+1
                  #IO.puts "done one process count #{count}"
                  numNodes = numNodes - 1
          {:not_done} -> #IO.puts "not converged"
                          numNodes = numNodes - 1
        end
        #IO.puts numNodes
      if(numNodes != 0) do
          main_receive(numNodes, startTime, count)
      else
          IO.puts "Program done!"
          endTime = :os.system_time(:millisecond)
          total = endTime - startTime
          IO.puts "Total time: #{total} ms"
          IO.puts "Nodes converged: #{count}"
      end
    end

      def start_link(process_id,topology,algorithm, numNodes) do
        #IO.puts "Server child #{process_id} starting..."
        id = via_tuple(process_id)
        GenServer.start_link(__MODULE__, {process_id, topology, algorithm, numNodes}, name: id)
      end

       def init({process_id, topology, algorithm, numNodes}) do
         parent=0
         if algorithm == "gossip" do
           receive_gossip(0, process_id, parent,0,topology)
         else
           s = process_id
           w = 1
           #receive_push_sum(process_id, s, w, parent, 0, topology, true, 0)
           push_sum(process_id, s, w, parent, topology, true, 0, [], numNodes)
         end
      end

      def push_sum(node, s_value, w_value, parent, topology, flag, count, neighbor_list, numNodes) do
        receive do
          {:start_push_sum, s, w, sender, receiver, parent} ->
            #IO.puts "S: #{s_value} W: #{w_value}"
            #IO.puts "From #{sender} to #{receiver}"
            #parent_node = parent
            o_ratio = s_value/w_value
            #IO.puts o_ratio
            w_value = w_value + w
            s_value = s_value + s

            if flag == true do
              #ptokill = spawn(__MODULE__, :send_push_sum, [receiver, numNodes, rumor, getLineNeighbors(receiver,numNodes), s_value, w_value, parent])
              #neighbor_list =  getLineNeighbors(receiver, numNodes)
              cond do
                topology == "line" -> neighbor_list = getLineNeighbors(node, numNodes)
                topology == "full" -> neighbor_list = getFullNeighbor([],1,node, numNodes)
                topology == "2D" -> neighbor_list = getPerfect2dNeighbor(node, numNodes)
                topology == "imp2D" -> neighbor_list = getImperfect2dNeighbor(node, numNodes)
              end
              flag = false
            end
            n_ratio = s_value/w_value
            #IO.puts "s/w ratio of converged node #{node} => #{s_value}"
            diff = abs(n_ratio - o_ratio)
            if diff < :math.pow(10, -10) do
              count = count + 1
              #IO.puts "Incremeting counter, counter: #{count}"
              if count == 3 do
                send parent, {:done}
                IO.puts "s/w ratio of converged node #{node} => #{s_value} : #{w_value} : #{s_value/w_value}"
                #Process.exit(ptokill, :kill)
                Process.exit(self(), :kill)
              else
                #receive_push_sum(node, s_value, w_value, parent, ptokill, topology, flag, count)
                send_code(node, neighbor_list, s_value, w_value, parent, count, flag, numNodes, topology)
                #:timer.sleep(10)
                push_sum(node, s_value, w_value, parent, topology, flag, count, neighbor_list, numNodes)
              end
            else
              #receive_push_sum(node, s_value, w_value, parent, ptokill, topology, flag, 0)
              send_code(node, neighbor_list, s_value, w_value, parent, 0, flag, numNodes, topology)
              #:timer.sleep(10)
              push_sum(node, s_value, w_value, parent, topology, flag, 0, neighbor_list, numNodes)
            end
          # {:finish} -> IO.puts "#{s_value}  : #{w_value}"
          #              send parent, {:not_done}
          #              Process.exit(ptokill, :kill)

        after 500 ->
                    if flag == true do
                      #ptokill = spawn(__MODULE__, :send_push_sum, [receiver, numNodes, rumor, getLineNeighbors(receiver,numNodes), s_value, w_value, parent])
                      push_sum(node, s_value, w_value, parent, topology, flag, count, neighbor_list, numNodes)
                    else
                      send_code(node, neighbor_list, s_value, w_value, parent, count, flag, numNodes, topology)
                  end

        end
      end

      def send_code(node,neighbor_list,s_value, w_value, parent, count, flag, numNodes, topology) do
        if(List.last(neighbor_list) != nil)  do
          neighbor = Enum.random(neighbor_list)
          :timer.sleep(1)
          pid = whereis(neighbor)
          case pid do
            nil -> neighbor_list = List.delete(neighbor_list, neighbor)
                   push_sum(node, s_value, w_value, parent, topology, flag, count, neighbor_list, numNodes)
            pid -> send pid, {:start_push_sum, s_value/2, w_value/2, node, neighbor, parent}
                   push_sum(node, s_value/2, w_value/2, parent, topology, flag, count, neighbor_list, numNodes)
          end
          #send_push_sum(sender, numNodes, rumor, neighbor_list, s_value/2, w_value/2, parent)
          #:timer.sleep(10)

        else
          send parent, {:not_done}
          IO.puts "s/w ratio of not - converged node #{node} => #{s_value} : #{w_value} : #{s_value/w_value}"
          Process.exit(self(), :kill)
        end
      end

      def receive_push_sum(node, s_value, w_value, parent, ptokill, topology, flag, count) do
       receive do
         {:start_push_sum, rumor, s, w, sender, receiver, numNodes, parent} ->
           #IO.puts "S: #{s_value} W: #{w_value}"
           #IO.puts "From #{sender} to #{receiver}"
           #parent_node = parent
           o_ratio = s_value/w_value
           IO.puts o_ratio
           w_value = w_value + w
           s_value = s_value + s

           if flag == true do
             ptokill = spawn(__MODULE__, :send_push_sum, [receiver, numNodes, rumor, getLineNeighbors(receiver,numNodes), s_value, w_value, parent])
             flag = false
           end
           n_ratio = s_value/w_value

           diff = abs(n_ratio - o_ratio)
           if diff < :math.pow(10, -10) do
             count = count + 1
             #IO.puts "Incremeting counter, counter: #{count}"
             if count == 3 do
               send parent, {:done}
               IO.puts "#{s_value}  : #{w_value}"
               Process.exit(ptokill, :kill)
               Process.exit(self(), :kill)
             else
               receive_push_sum(node, s_value, w_value, parent, ptokill, topology, flag, count)
             end
           else
             receive_push_sum(node, s_value, w_value, parent, ptokill, topology, flag, 0)
           end
         {:finish} -> IO.puts "#{s_value}  : #{w_value}"
                      send parent, {:not_done}
                      Process.exit(ptokill, :kill)
       end
     end

     def send_push_sum(sender, numNodes, rumor, neighbor_list, s_value, w_value, parent) do
       if(List.last(neighbor_list) != nil)  do
         neighbor = Enum.random(neighbor_list)
         :timer.sleep(1)
         pid = whereis(neighbor)
         case pid do
           nil -> neighbor_list = List.delete(neighbor_list, neighbor)
           pid -> send pid, {:start_push_sum, rumor, s_value/2, w_value/2, sender, neighbor, numNodes, parent}
         end
         send_push_sum(sender, numNodes, rumor, neighbor_list, s_value/2, w_value/2, parent)
       else
         send whereis(sender), {:finish}
         Process.exit(self(), :kill)
       end
     end

      def receive_gossip(count, process_id, parent, ptokill,topology) do
        receive do
            {:start, rumor, sender, receiver, numNodes, father} ->
                      parent = father
                        if sender == 0 do
                          IO.puts "Starting from #{receiver}"
                        else
                          #IO.puts "received from #{sender} in #{receiver}"
                        end
                        #spawn to start_gossip_line
                        if(count == 0) do
                          cond do
                            topology == "line" -> ptokill = spawn(__MODULE__,:start_gossip_line,[receiver, numNodes, rumor ,getLineNeighbors(receiver,numNodes), parent])
                            topology == "full" -> ptokill = spawn(__MODULE__,:start_gossip_line,[receiver, numNodes, rumor ,getFullNeighbor([],1,receiver,numNodes), parent])
                            topology == "2D" -> ptokill = spawn(__MODULE__,:start_gossip_line,[receiver, numNodes, rumor ,getPerfect2dNeighbor(receiver,numNodes), parent])
                            topology == "imp2D" -> ptokill = spawn(__MODULE__,:start_gossip_line,[receiver, numNodes, rumor ,getImperfect2dNeighbor(receiver,numNodes), parent])
                          end
                      end

             {:finish} -> #IO.puts "finissfadsvdsvdsvsdvdsvsdvsdvsdvsdvsdvdsvds"
                          send parent,{:not_done}
                          Process.exit(self(),:kill)
             _ -> nil
          end
          if(count<10) do
            receive_gossip(count+1,process_id,parent, ptokill,topology)
          else
            #IO.puts "Killing process_id #{process_id} sender"
            send parent, {:done}
            Process.exit(ptokill, :kill)
          end
      end

      def start_gossip_line(node, numNodes, rumor, neighbors_list, parent) do
        if(List.last(neighbors_list) != nil) do
          neighbor = Enum.random(neighbors_list)
          :timer.sleep(1)
          #IO.inspect whereis(node)
          pid = whereis(neighbor)
          case pid do
            nil -> #IO.puts "No neighbor exists in gossip line for process #{node}"
                  neighbors_list = List.delete(neighbors_list,neighbor)
            pid -> send pid, {:start, rumor , node, neighbor, numNodes, parent}
          end
          start_gossip_line(node, numNodes,rumor,neighbors_list, parent)
         else
              #:timer.sleep(1000)
              #IO.puts node
              #IO.puts "sfvsdbfsvsfvsvdssd"
              #if(whereis(node)!=nil) do

              send whereis(node), {:finish}
              #end
              Process.exit(self(),:kill)
         end
      end

      defp via_tuple(id), do: {:via, Registry, {@process_registry_name, id}}

      def unregister(process_id) do
        IO.puts "Unregistered process #{process_id}"
        Registry.update_value(@process_registry_name,process_id, fn -> "sdsdfs" end)
        IO.inspect Registry.lookup(@process_registry_name,process_id)
      end

      def whereis(account_id) do
        case Registry.lookup(@process_registry_name, account_id) do
          [{pid, _}] -> pid
          [] -> nil
        end
      end

      def populate_processes(numNodes, topology, algorithm) do
        for i <- 1..numNodes do
          #spawn(fn -> start_link(i) end)
          spawn(__MODULE__,:start_link,[i,topology,algorithm,numNodes])
        end
      end

      def getLineNeighbors(node,numNodes) do
        if(node==1 || node == numNodes) do
          if(node == 1 ) do
            node = [2]
          else
            node = [numNodes-1]
        end
        else
          node = [node+1, node-1]
        end
        node
      end

      def getFullNeighbor(list, index, node, numNodes) do
      # #  neighbor = :rand.uniform(numNodes)
      # #   if(neighbor == node) do
      # #     getFullNeighbor(node,numNodes)
      # #   else
      # #      neighbor
      # #   end
      # neighbors_list = []
      # for i <- 1..numNodes do
      #         neighbors_list = List.insert_at(neighbors_list,i-1,i)
      #         IO.inspect neighbors_list
      # end
      # neighbors_list
        if index <= numNodes do
          if index != node do
            getFullNeighbor(List.insert_at(list,0,index),index+1,node,numNodes)
          else
            getFullNeighbor(list,index + 1,node, numNodes)
          end
        else
          list
        end

      end

      defp create2dGrid(node,numNodes) do
        root = round(:math.ceil(:math.sqrt(numNodes)))
        numNodes = round(:math.pow(root,2))
        neighbors_list = []
        if(node - root > 0) do
          neighbors_list = [node-root | neighbors_list]
        end
        if( (rem(node-1,root)!= root) && (node-1)>0
                && rem(node-1,root)!=0  ) do
          neighbors_list = [node-1 | neighbors_list]
        end
        if( rem(node+1,root)!=root && (node+1)<=numNodes
                && rem(node+1,root)!=1) do
          neighbors_list = [node+1 | neighbors_list]
        end
        if( (node+root) <=numNodes) do
          neighbors_list = [node+root | neighbors_list]
        end
        neighbors_list
      end

    def getPerfect2dNeighbor(node, numNodes) do
        #Enum.random(create2dGrid(node,numNodes))
        create2dGrid(node, numNodes)
    end

    def getImperfect2dNeighbor(node,numNodes) do
      neighbors_list = create2dGrid(node, numNodes)
      neighbors_list = getImp(node,numNodes, neighbors_list)
      neighbors_list
    end

    def getImp(node,numNodes, neighbors_list) do
      #neighbors_list = create2dGrid(node,numNodes)
      random_node = :rand.uniform(numNodes)
      if(Enum.member?(neighbors_list, random_node) || random_node==node) do
        getImp(node,numNodes, neighbors_list)
      else
        #Enum.random([random_node|neighbors_list])
        neighbors_list = [random_node|neighbors_list]
      end
        neighbors_list
    end

    def isListNil do
        list = [nil]
        list2 = [1,nil]
        list3 = [1,2,3]
        list4 = [nil,nil]
      #   IO.puts Enum.all?(list, fn(x) -> x == nil end)
      #   IO.puts Enum.all?(list2, fn(x) -> x == nil end)
      #   IO.puts Enum.all?(list3, fn(x) -> x == nil end)
      #   IO.puts Enum.all?(list4, fn(x) -> x == nil end)
        newlist = List.delete(list,nil)
        IO.inspect newlist
        IO.puts Enum.all?(newlist, fn(x) -> x == nil end)
      #   if(Enum.all?(list, fn(x) -> x == nil end)) do
      #       IO.puts "prints true"
      #   else
      #     IO.puts "prints false"
      #   end
      if(List.last(newlist) == nil) do
          IO.puts "nil"
      else
          IO.puts "not nil"
      end

    end

  end
