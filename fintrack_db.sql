-- Create User Table
CREATE TABLE Users (
    user_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone_number VARCHAR(20) UNIQUE NOT NULL
);

-- Create Portfolio Table (1:M relationship with User)
CREATE TABLE Portfolio (
    portfolio_id SERIAL PRIMARY KEY,
    user_id INT NOT NULL,
    portfolio_name VARCHAR(255) NOT NULL,
    risk_profile VARCHAR(10) CHECK (risk_profile IN ('High', 'Medium', 'Low')),
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE
);

-- Create Goal Table (1:M relationship with User)
CREATE TABLE Goal (
    goal_id SERIAL PRIMARY KEY,
    user_id INT NOT NULL,
    goal_name VARCHAR(255) NOT NULL,
    target_amount DECIMAL(15,2) NOT NULL,
    achieved_amount DECIMAL(15,2) NOT NULL,
    target_date DATE NOT NULL,
    goal_status VARCHAR(15) CHECK (goal_status IN ('Achieved', 'In Progress')),
    priority_level VARCHAR(10) CHECK (priority_level IN ('High', 'Medium', 'Low')),
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE
);

-- Create Investment
CREATE TABLE Investment (
    investment_id SERIAL PRIMARY KEY,
    portfolio_id INT NOT NULL,
    security_name VARCHAR(255) NOT NULL,
    investment_type VARCHAR(255) NOT NULL,
    amount_invested DECIMAL(15,2) NOT NULL,
    current_value DECIMAL(15,2) NOT NULL,
    purchase_date DATE NOT NULL,
    status VARCHAR(10) CHECK (status IN ('Sold', 'Active')),
    FOREIGN KEY (portfolio_id) REFERENCES Portfolio(portfolio_id) ON DELETE CASCADE
);

-- Create Transaction
CREATE TABLE Transaction (
    transaction_id SERIAL PRIMARY KEY,
    investment_id INT NOT NULL,
    transaction_type VARCHAR(10) CHECK (transaction_type IN ('Buy', 'Sell')),
    transaction_date DATE NOT NULL,
    transaction_amount DECIMAL(15,2) NOT NULL,
    units INT NOT NULL,
    broker_fees DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (investment_id) REFERENCES Investment(investment_id) ON DELETE CASCADE
);

-- Create Returns
CREATE TABLE Returns (
    return_id SERIAL PRIMARY KEY,
    investment_id INT NOT NULL,
    goal_id INT NOT NULL,
    date DATE NOT NULL,
    return_amount DECIMAL(15,2) NOT NULL,
    cumulative_return DECIMAL(15,2) NOT NULL,
    FOREIGN KEY (investment_id) REFERENCES Investment(investment_id) ON DELETE CASCADE,
    FOREIGN KEY (goal_id) REFERENCES Goal(goal_id) ON DELETE CASCADE
);

--adding data to tables
copy Users(user_id,name, email, phone_number) FROM 'G:\DBMS\project\users.csv' DELIMITER ',' CSV HEADER;
copy Portfolio(portfolio_id,user_id, portfolio_name, risk_profile) FROM 'G:\DBMS\project\portfolio.csv' DELIMITER ',' CSV HEADER;
copy Goal(goal_id,user_id, goal_name, target_amount, achieved_amount, target_date, goal_status, priority_level) FROM 'G:\DBMS\project\goal.csv' DELIMITER ',' CSV HEADER;
copy Investment(investment_id,portfolio_id, security_name, investment_type, amount_invested, current_value, purchase_date, status) FROM 'G:\DBMS\project\investment.csv' DELIMITER ',' CSV HEADER;
copy Transaction(transaction_id,investment_id, transaction_type, transaction_date, transaction_amount, units, broker_fees) FROM 'G:\DBMS\project\transactiontable.csv' DELIMITER ',' CSV HEADER;
copy Returns(return_id,investment_id, goal_id, date, return_amount, cumulative_return) FROM 'G:\DBMS\project\returntable.csv' DELIMITER ',' CSV HEADER;

DROP TABLE IF EXISTS ReturnTable;
DROP TABLE IF EXISTS TransactionTable;
DROP TABLE IF EXISTS Investment;
DROP TABLE IF EXISTS Goal;
DROP TABLE IF EXISTS Portfolio;
DROP TABLE IF EXISTS Users;

select * from users;
select * from portfolio;
select * from returns;
select * from investment;
select * from goal;
select * from transaction;


CREATE FUNCTION GetPortfolioValue(portfolioid INT) 
RETURNS DECIMAL AS $$
DECLARE
    total_value DECIMAL;
BEGIN
    SELECT SUM(current_value) INTO total_value 
    FROM Investment WHERE portfolio_id = portfolioid;
    
    RETURN total_value;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS GetPortfolioValue(INT);
SELECT GetPortfolioValue(397);

CREATE FUNCTION IsGoalMet(goalid INT) 
RETURNS BOOLEAN AS $$
DECLARE
    target DECIMAL;
    achieved DECIMAL;
BEGIN
    SELECT Target_Amount, Achieved_Amount INTO target, achieved 
    FROM Goal WHERE Goal_id = goalid;

    RETURN achieved >= target;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS IsGoalMet(INT);
select IsGoalMet(394);

CREATE FUNCTION GetInvestmentPerformance(investmentid INT) 
RETURNS DECIMAL AS $$
DECLARE
    invested DECIMAL;
    current DECIMAL;
BEGIN
    SELECT Amount_Invested, Current_Value INTO invested, current 
    FROM Investment WHERE Investment_id = investmentid;

    RETURN ((current - invested) / invested) * 100;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS GetInvestmentPerformance(INT);
select GetInvestmentPerformance(619);

CREATE FUNCTION GetTotalUserReturns(userid INT) 
RETURNS DECIMAL AS $$
DECLARE
    total_returns DECIMAL;
BEGIN
    SELECT COALESCE(SUM(Return_Amount), 0) INTO total_returns 
    FROM Returns
    WHERE Investment_id IN (
        SELECT Investment_id FROM Investment WHERE Portfolio_id IN (
            SELECT Portfolio_id FROM Portfolio WHERE User_id = userid
        )
    );
    RETURN total_returns;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS GetTotalUserReturns(INT);
select GetTotalUserReturns(50); 

CREATE OR REPLACE FUNCTION CountActiveInvestments(portfolioid INT) 
RETURNS INT AS $$
DECLARE
    active_count INT;
BEGIN
    SELECT COUNT(*) INTO active_count 
    FROM Investment 
    WHERE Portfolio_ID = portfolioid AND Status = 'Active';

    RETURN active_count;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS CountActiveInvestments(portfolioid INT);
select CountActiveInvestments(397);

--for admin page
CREATE OR REPLACE FUNCTION get_user_summary(p_user_id INT)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'user_name', u.name,
        'total_portfolios', COALESCE(p.cnt, 0),
        'total_invested_amount', COALESCE(inv.total_amount, 0),
        'total_current_value', COALESCE(inv.current_value, 0),
        'total_goals', COALESCE(goal_counts.total_goals, 0),
        'goals_achieved', COALESCE(goal_counts.goals_achieved, 0)
    )
    INTO result
    FROM users u
    LEFT JOIN (
        SELECT user_id, COUNT(*) AS cnt
        FROM portfolio
        WHERE user_id = p_user_id
        GROUP BY user_id
    ) p ON u.user_id = p.user_id
    LEFT JOIN (
        SELECT p.user_id,
               SUM(i.amount_invested) AS total_amount,
               SUM(i.current_value) AS current_value
        FROM investment i
        JOIN portfolio p ON i.portfolio_id = p.portfolio_id
        WHERE p.user_id = p_user_id
        GROUP BY p.user_id
    ) inv ON u.user_id = inv.user_id
    LEFT JOIN (
        SELECT user_id,
               COUNT(*) AS total_goals,
               COUNT(*) FILTER (WHERE goal_status = 'Achieved') AS goals_achieved
        FROM goal
        WHERE user_id = p_user_id
        GROUP BY user_id
    ) goal_counts ON u.user_id = goal_counts.user_id
    WHERE u.user_id = p_user_id;

    RETURN result;
END;
$$;

select get_user_summary(50);

-- Trigger function to auto-update goal status
CREATE OR REPLACE FUNCTION trg_check_goal_met()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM goal WHERE goal_id = NEW.goal_id AND achieved_amount >= target_amount
    ) THEN
        UPDATE goal SET goal_status = 'Achieved' WHERE goal_id = NEW.goal_id;
    ELSE
        UPDATE goal SET goal_status = 'In Progress' WHERE goal_id = NEW.goal_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger on update of achieved amount
CREATE TRIGGER trg_goal_achievement
AFTER UPDATE OF achieved_amount ON goal
FOR EACH ROW
EXECUTE FUNCTION trg_check_goal_met();

-- Trigger function to log performance change
CREATE OR REPLACE FUNCTION trg_log_investment_performance()
RETURNS TRIGGER AS $$
DECLARE
    perf DECIMAL;
BEGIN
    perf := GetInvestmentPerformance(NEW.investment_id);
    RAISE NOTICE 'Updated Performance for Investment %: %%%', NEW.investment_id, perf;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger on investment value update
CREATE TRIGGER trg_investment_perf_update
AFTER UPDATE OF current_value ON investment
FOR EACH ROW
EXECUTE FUNCTION trg_log_investment_performance();
DROP TRIGGER IF EXISTS trg_investment_perf_update ON Investment;
DROP FUNCTION IF EXISTS trg_log_investment_performance();


-- Trigger function to notify count of active investments
CREATE OR REPLACE FUNCTION trg_notify_active_investments()
RETURNS TRIGGER AS $$
DECLARE
    count_active INT;
BEGIN
    count_active := CountActiveInvestments(NEW.portfolio_id);
    RAISE NOTICE 'Total Active Investments in Portfolio %: %', NEW.portfolio_id, count_active;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger after inserting new investment
CREATE TRIGGER trg_active_investment_count
AFTER INSERT ON investment
FOR EACH ROW
WHEN (NEW.Status = 'Active')
EXECUTE FUNCTION trg_notify_active_investments();

-- Trigger function to recalculate and log user returns
CREATE OR REPLACE FUNCTION trg_recalculate_user_returns()
RETURNS TRIGGER AS $$
DECLARE
    uid INT;
    total_ret DECIMAL;
BEGIN
    SELECT user_ID INTO uid
    FROM Portfolio
    WHERE Portfolio_ID = (
        SELECT Portfolio_ID FROM investment WHERE investment_id = NEW.investment_id
    );

    total_ret := GetTotalUserReturns(uid);
    RAISE NOTICE 'Total Returns for User %: ₹%', uid, total_ret;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_user_return_update ON Returns;
DROP FUNCTION IF EXISTS trg_recalculate_user_returns();

-- Trigger after a new return is added
CREATE TRIGGER trg_user_return_update
AFTER INSERT ON returns
FOR EACH ROW
EXECUTE FUNCTION trg_recalculate_user_returns();


CREATE OR REPLACE FUNCTION log_investment_creation()
RETURNS TRIGGER AS $$
BEGIN
    RAISE NOTICE 'New Investment Added: % in Portfolio % (Amount: ₹%)',
        NEW.security_name, NEW.portfolio_id, NEW.amount_invested;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_log_investment_creation
AFTER INSERT ON Investment
FOR EACH ROW
EXECUTE FUNCTION log_investment_creation();


CREATE VIEW investor_portfolio_view AS
SELECT u.name, p.portfolio_name, i.security_name, i.current_value
FROM Users u
JOIN Portfolio p ON u.user_id = p.user_id
JOIN Investment i ON p.portfolio_id = i.portfolio_id;

select * from investor_portfolio_view where name='User50';

CREATE VIEW UserInvestmentSummaryView AS
SELECT 
    u.user_id,
    u.name AS user_name,
    SUM(i.amount_invested) AS total_amount_invested,
    SUM(i.current_value) AS total_current_value,
    ROUND(SUM(i.current_value - i.amount_invested), 2) AS net_gain_loss,
    ROUND((SUM(i.current_value - i.amount_invested) / NULLIF(SUM(i.amount_invested), 0)) * 100, 2) AS return_percentage
FROM Users u
JOIN Portfolio p ON u.user_id = p.user_id
JOIN Investment i ON p.portfolio_id = i.portfolio_id
GROUP BY u.user_id, u.name;


-- View for admins to monitor goal progress
CREATE VIEW admin_goal_progress AS
SELECT u.name, g.goal_name, g.achieved_amount, g.target_amount
FROM Users u
JOIN Goal g on u.user_id=g.user_id;

select * from 
-- Create admin role
CREATE ROLE admin WITH LOGIN PASSWORD 'adminpass';

GRANT EXECUTE ON FUNCTION get_user_summary(INT) TO admin;
REVOKE SELECT ON ALL TABLES IN SCHEMA public FROM admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO admin;


CREATE ROLE advisor WITH LOGIN PASSWORD 'advisorpass';

GRANT SELECT ON Goal TO advisor;
GRANT SELECT ON Returns TO advisor;
GRANT SELECT ON investment to advisor;

-- Grant EXECUTE access on the specific functions
GRANT EXECUTE ON FUNCTION GetTotalUserReturns(INT) TO advisor;
GRANT EXECUTE ON FUNCTION GetInvestmentPerformance to advisor;

CREATE ROLE fintrack_user WITH LOGIN PASSWORD 'fintrack_user';

GRANT SELECT ON Portfolio TO fintrack_user;
GRANT SELECT ON Goal TO fintrack_user;
GRANT SELECT ON Investment TO fintrack_user;
GRANT SELECT ON Transaction TO fintrack_user;
GRANT SELECT ON Returns TO fintrack_user;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO fintrack_user;

--Indices
CREATE index index_risk_profile on portfolio using HASH(risk_profile);
CREATE index index_return_amount on returns using BTREE(return_amount);
CREATE index index_target_date on goal using BTREE(target_date);
CREATE index index_units on transaction using HASH(units);
CREATE index index_transaction_type on transaction using HASH(transaction_type);
CREATE index index_broker_fees on transaction using BTREE(broker_fees);
CREATE index index_status on investment using HASH(status);

DROP INDEX IF EXISTS index_risk_profile;
DROP INDEX IF EXISTS index_return_amount;
DROP INDEX IF EXISTS index_target_date;
DROP INDEX IF EXISTS index_units;
DROP INDEX IF EXISTS index_transaction_type;
DROP INDEX IF EXISTS index_broker_fees;

--query using hash index
SELECT 
    u.user_id,
    u.name AS user_name,
    u.email,
    p.portfolio_id,
    p.portfolio_name,
    p.risk_profile,
    COALESCE(SUM(i.amount_invested), 0) AS total_invested
FROM 
    Portfolio p
JOIN 
    Users u ON u.user_id = p.user_id
LEFT JOIN 
    Investment i ON i.portfolio_id = p.portfolio_id
WHERE 
    p.risk_profile = 'High'  -- This uses the hash index
GROUP BY 
    u.user_id, u.name, u.email, p.portfolio_id, p.portfolio_name, p.risk_profile
ORDER BY 
    u.name;


--query using btree index
EXPLAIN ANALYZE
SELECT 
    r.return_id,
    r.investment_id,
    r.goal_id,
    r.date,
    r.return_amount,
    r.cumulative_return
FROM Returns r
WHERE r.return_amount > 1000
ORDER BY r.return_amount DESC
LIMIT 5;

--query using btree index
EXPLAIN ANALYZE
SELECT 
    goal_id,
    goal_name,
    target_amount,
    achieved_amount,
    target_date,
    goal_status
FROM Goal
WHERE target_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'
ORDER BY target_date ASC;

--query using btree and hash index
EXPLAIN ANALYZE
SELECT i.security_name, t.transaction_type, t.transaction_date, t.transaction_amount,t.broker_fees
FROM Transaction t
JOIN Investment i ON t.investment_id = i.investment_id
WHERE t.units = 100
  AND t.transaction_type = 'Buy'
  AND t.broker_fees < 50
ORDER BY t.transaction_date DESC;

--for checking privileges 
INSERT INTO Portfolio (UserID, PortfolioName, CreatedDate)
VALUES (1,5001, 'My New Investment Portfolio', CURRENT_DATE);

--query using  GetPortfolioValue(p.portfolio_id)
SELECT 
    p.portfolio_id,
    p.portfolio_name,
    u.name AS user_name,
    p.risk_profile,
    GetPortfolioValue(p.portfolio_id) AS total_portfolio_value
FROM 
    Portfolio p
JOIN 
    Users u ON p.user_id = u.user_id
WHERE 
    p.portfolio_id = 397 ;

--query using IsGoalMet(g.goal_id)
SELECT 
    g.goal_id,
    g.goal_name,
    g.target_amount,
    g.achieved_amount,
    g.target_date,
    g.goal_status,
    IsGoalMet(g.goal_id) AS is_goal_achieved
FROM 
    Goal g
JOIN 
    Users u ON g.user_id = u.user_id
WHERE 
    g.goal_id = 394;


--query using GetInvestmentPerformance(i.investment_id)
SELECT 
    i.investment_id,
    i.security_name,
    i.investment_type,
    i.amount_invested,
    i.current_value,
    i.status,
    p.portfolio_name,
    GetInvestmentPerformance(i.investment_id) AS performance_percentage
FROM 
    Investment i
JOIN 
    Portfolio p ON i.portfolio_id = p.portfolio_id
WHERE 
    i.investment_id = 619;

--query using GetTotalUserReturns(u.user_id)
SELECT 
    u.user_id,
    u.name AS user_name,
    u.email,
    GetTotalUserReturns(u.user_id) AS total_returns
FROM 
    Users u
WHERE 
    u.user_id = 50;

--query using get_user_summary(u.user_id)
SELECT 
    u.user_id,
    u.name AS user_name,
    u.email,
    get_user_summary(u.user_id) AS detailed_summary
FROM 
    Users u
WHERE 
    u.user_id = 7;



