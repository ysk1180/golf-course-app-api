require 'rakuten_web_service'
require 'aws-record'

class SearchGolfApp # DynamoDBのテーブル名とする
  include Aws::Record
  integer_attr :golf_course_id, hash_key: true
  integer_attr :duration1
  integer_attr :duration2
end

def lambda_handler(event:, context:)
  date = event['date'].to_s.insert(4, '-').insert(7, '-') # GORAで必要な形に直している(例:20200520→2020-05-20)
  budget = event['budget']
  departure = event['departure']
  duration = event['duration']

  RakutenWebService.configure do |c|
    c.application_id = ENV['RAKUTEN_APPID']
    c.affiliate_id = ENV['RAKUTEN_AFID']
  end

  matched_plans = []
  plans = RakutenWebService::Gora::Plan.search(page: page,
                                               maxPrice: budget,
                                               playDate: date,
                                               areaCode: '8,11,12,13,14',
                                               NGPlan: 'planHalfRound,planLesson,planOpenCompe,planRegularCompe') # 除外条件をつけている(仕様:https://webservice.rakuten.co.jp/api/goraplansearch/)

  plans.each do |plan|
    plan_duration = Duration.find(golf_course_id: plan['golfCourseId']).send("duration#{departure}") # DynamoDBに保持している所要時間を取得
    next if plan_duration > duration # 希望の所要時間より長いものの場合はスキップ

    matched_plans.push(
      {
        plan_name: plan['planInfo'][0]['planName'],
        plan_id: plan['planInfo'][0]['planId'],
        course_name: plan['golfCourseName'],
        caption: plan['golfCourseCaption'],
        prefecture: plan['prefecture'],
        image_url: plan['golfCourseImageUrl'],
        evaluation: plan['evaluation'],
        price: plan['planInfo'][0]['price'],
        duration: plan_duration,
        reserve_url_pc: plan['planInfo'][0]['callInfo']['reservePageUrlPC'],
        stock_count: plan['planInfo'][0]['callInfo']['stockCount'],
      }
    )
  end

  matched_plans.sort_by! {|plan| plan[:duration]} # 所要時間が短い順にソートしている

  {
    count: matched_plans.count,
    plans: matched_plans
  }
end
