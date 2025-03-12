module GitGameShow
  class MiniGame
    class << self
      # Keep track of all subclasses (mini games)
      def descendants
        @descendants ||= []
      end

      def inherited(subclass)
        descendants << subclass
      end

      attr_accessor :name, :description, :example, :questions_per_round
    end

    # Default number of questions per round
    self.questions_per_round = 5

    # Default name and description
    self.name = "Base Mini Game"
    self.description = "This is a base mini game class. You should not see this in the actual game."

    # Method to generate questions based on Git repo data
    # This should be overridden by subclasses
    def generate_questions(repo)
      raise NotImplementedError, "#{self.class} must implement #generate_questions"
    end

    # Method to evaluate player answers and return results
    # This should be overridden by subclasses
    def evaluate_answers(question, player_answers)
      raise NotImplementedError, "#{self.class} must implement #evaluate_answers"
    end

    # Helper method to get all commits from a repo
    def get_all_commits(repo)
      # Get a larger number of commits to ensure more diversity
      repo.log(1000).each.to_a
    end

    # Helper method to get unique authors from commits
    def get_commit_authors(commits)
      commits.map { |commit| commit.author.name }.uniq
    end

    # Helper method to get commit messages
    def get_commit_messages(commits)
      commits.map(&:message)
    end

    # Helper method to shuffle an array with the option to exclude certain items
    def shuffled_excluding(array, exclude = nil)
      items = exclude ? array.reject { |item| item == exclude } : array.dup
      items.shuffle
    end
  end
end
