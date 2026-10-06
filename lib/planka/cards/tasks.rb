module Planka
  module Cards
    # Completes one native ordinary task, independently of workflow criteria.
    class Tasks
      OPERATION_ERRORS = [Planka::Error, *Client::NETWORK_ERRORS].freeze

      def self.read(client, reference, card:, completed:, base_url:)
        response = client.card(card)
        unless response['item'].is_a?(Hash) && response['item']['id'] == card && response['included'].is_a?(Hash)
          raise InvalidResponse, 'Invalid task card'
        end
        included = response.fetch('included')
        lists, tasks = included.values_at('taskLists', 'tasks')
        unless lists.is_a?(Array) && lists.all? { |list| list.is_a?(Hash) && list['cardId'] == card && list['id'].is_a?(String) } && tasks.is_a?(Array) && tasks.all? { |task| task.is_a?(Hash) && task['id'].is_a?(String) && task['name'].is_a?(String) && [true, false].include?(task['isCompleted']) && lists.any? { |list| list['id'] == task['taskListId'] } }
          raise InvalidResponse, 'Invalid card task records'
        end
        task = Reference.resolve(tasks, reference, resource: 'task', scope: 'the card')
        raise ReferenceError.new('Linked tasks follow their blocker card; never complete them manually', code: 'linked_task', status: 1) if task['linkedCardId']
        data = task.slice('id', 'name', 'taskListId', 'isCompleted').merge('cardId' => card)
        return MutationResult.new(data: data, changed: false) if task['isCompleted'] == completed
        mutate(client, data, completed)
      end

      def self.mutate(client, data, completed)
        updated = client.update_task(data['id'], isCompleted: completed)
        unless updated.is_a?(Hash) && updated['id'] == data['id'] && updated['taskListId'] == data['taskListId'] && updated['isCompleted'] == completed
          raise InvalidResponse, 'Invalid task update response'
        end
        MutationResult.new(data: data.merge('isCompleted' => completed), changed: true)
      rescue *OPERATION_ERRORS => error
        uncertain = !Client.unapplied?(error)
        raise MutationFailure.new(data: data.merge('isCompleted' => uncertain ? nil : !completed),
          changed: uncertain ? nil : false, uncertain: uncertain,
          recovery: { 'action' => 'readback-task', 'resources' => [{ 'type' => 'card', 'id' => data['cardId'] }, { 'type' => 'task', 'id' => data['id'] }] })
      end
      private_class_method :mutate
    end
  end
end
