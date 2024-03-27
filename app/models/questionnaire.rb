class Questionnaire < ApplicationRecord
  # for doc on why we do it this way,
  # see http://blog.hasmanythrough.com/2007/1/15/basic-rails-association-cardinality
  has_many :questions, dependent: :destroy # the collection of questions associated with this Questionnaire
  belongs_to :instructor # the creator of this questionnaire
  has_many :assignment_questionnaires, dependent: :destroy
  has_many :assignments, through: :assignment_questionnaires
  has_one :questionnaire_node, foreign_key: 'node_object_id', dependent: :destroy, inverse_of: :questionnaire

  validate :validate_questionnaire
  validates :name, presence: true
  validates :max_question_score, :min_question_score, numericality: true

  DEFAULT_MIN_QUESTION_SCORE = 0  # The lowest score that a reviewer can assign to any questionnaire question
  DEFAULT_MAX_QUESTION_SCORE = 5  # The highest score that a reviewer can assign to any questionnaire question
  DEFAULT_QUESTIONNAIRE_URL = 'http://www.courses.ncsu.edu/csc517'.freeze
  QUESTIONNAIRE_TYPES = ['ReviewQuestionnaire',
                         'MetareviewQuestionnaire',
                         'Author FeedbackQuestionnaire',
                         'AuthorFeedbackQuestionnaire',
                         'Teammate ReviewQuestionnaire',
                         'TeammateReviewQuestionnaire',
                         'SurveyQuestionnaire',
                         'AssignmentSurveyQuestionnaire',
                         'Assignment SurveyQuestionnaire',
                         'Global SurveyQuestionnaire',
                         'GlobalSurveyQuestionnaire',
                         'Course SurveyQuestionnaire',
                         'CourseSurveyQuestionnaire',
                         'Bookmark RatingQuestionnaire',
                         'BookmarkRatingQuestionnaire',
                         'QuizQuestionnaire'].freeze
  has_paper_trail

  def get_weighted_score(assignment, scores)
    # create symbol for "varying rubrics" feature -Yang
    round = AssignmentQuestionnaire.find_by(assignment_id: assignment.id, questionnaire_id: id).used_in_round
    questionnaire_symbol = if round.nil?
                             symbol
                           else
                             (symbol.to_s + round.to_s).to_sym
                           end
    compute_weighted_score(questionnaire_symbol, assignment, scores)
  end

  def compute_weighted_score(symbol, assignment, scores)
    aq = assignment_questionnaires.find_by(assignment_id: assignment.id)
    if scores[symbol][:scores][:avg].nil?
      0
    else
      scores[symbol][:scores][:avg] * aq.questionnaire_weight / 100.0
    end
  end

  # Does this questionnaire contain true/false questions?
  def true_false_questions?
    questions.each { |question| return true if question.type == 'Checkbox' }
    false
  end

  def delete
    assignments.each do |assignment|
      raise "The assignment #{assignment.name} uses this questionnaire.
            Do you want to <A href='../assignment/delete/#{assignment.id}'>delete</A> the assignment?"
    end

    questions.each(&:delete)

    node = QuestionnaireNode.find_by(node_object_id: id)
    node.destroy if node

    destroy
  end

  def max_possible_score
    results = Questionnaire.joins('INNER JOIN questions ON questions.questionnaire_id = questionnaires.id')
                           .select('SUM(questions.weight) * questionnaires.max_question_score as max_score')
                           .where('questionnaires.id = ?', id)
    results[0].max_score
  end

  # clones the contents of a questionnaire, including the questions and associated advice
  def self.copy_questionnaire_details(params, instructor_id)
    orig_questionnaire = Questionnaire.find(params[:id])
    questions = Question.where(questionnaire_id: params[:id])
    questionnaire = orig_questionnaire.dup
    questionnaire.instructor_id = instructor_id
    questionnaire.name = 'Copy of ' + orig_questionnaire.name
    questionnaire.created_at = Time.zone.now
    questionnaire.save!
    questions.each do |question|
      new_question = question.dup
      new_question.questionnaire_id = questionnaire.id
      new_question.size = '50,3' if (new_question.is_a?(Criterion) || new_question.is_a?(TextResponse)) && new_question.size.nil?
      new_question.save!
      advices = QuestionAdvice.where(question_id: question.id)
      next if advices.empty?

      advices.each do |advice|
        new_advice = advice.dup
        new_advice.question_id = new_question.id
        new_advice.save!
      end
    end
    questionnaire
  end

  # validate the entries for this questionnaire
  def validate_questionnaire
    errors.add(:max_question_score, 'The maximum question score must be a positive integer.') if max_question_score < 1
    errors.add(:min_question_score, 'The minimum question score must be a positive integer.') if min_question_score < 0
    errors.add(:min_question_score, 'The minimum question score must be less than the maximum.') if min_question_score >= max_question_score

    results = Questionnaire.where('id <> ? and name = ? and instructor_id = ?', id, name, instructor_id)
    errors.add(:name, 'Questionnaire names must be unique.') if results.present?
  end

  # A row_hash here is a question that gets added to the questionnaire
  #
  # NOTE: Assuming rows have headers :question, :type, :weight, :param
  # in that specific order. Also need advice with string score
  def self.import(row_hash, _session = nil, id)
    raise ArgumentError, 'Record does not contain required items.' if row_hash.length < required_import_fields.length

    questionnaire = Questionnaire.find(id)
    raise ImportError, 'Questionnaire with provided ID does not exist.' if questionnaire.nil?

    # Question with required fields
    q = Question.new
    q.type = row_hash[:type]
    q.txt = row_hash[:txt]
    q.weight = row_hash[:weight].to_i
    q.seq = row_hash[:seq].to_i

    # Optional fields
    q.break_before = (row_hash[:break_before] || 'true')
    q.size = row_hash[:size] if row_hash[:size]

    # Add question advice
    row_hash.each_key do |k|
      # Check score within range
      k = k.to_s
      next unless k =~ 'advice*'
      score = k.delete('advice_')
      next unless score.to_i >= questionnaire.min_question_score && score.to_i <= questionnaire.max_question_score
      a = QuestionAdvice.create!(score: k.to_i, advice: row_hash[k])
      q.question_advices << a
    end
    q.save!
    questionnaire.questions << q
  end

  def self.required_import_fields
    { 'txt' => 'Question text',
      'type' => 'Question type',
      'seq' => 'Sequence (for order)',
      'weight' => 'Point value' }
  end

  def self.optional_import_fields(id)
    quest = Questionnaire.find(id)
    optional_fields = { 'size' => 'Size of question',
                        'break_before' => 'Break before' }

    return optional_fields if quest.nil?
    
    quest.min_question_score..quest.max_question_score.each do |q|
      optional_fields['advice_' + q.to_s] = 'Advice ' + q.to_s
    end
    optional_fields
  end

  def self.import_options
    {}
  end
end
